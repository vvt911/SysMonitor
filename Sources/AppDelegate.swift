import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()

    /// Thứ tự từ trái sang phải trên thanh menu.
    private var controllers: [MetricController] = []
    /// Thanh menu thiếu chỗ thì bỏ từ cuối danh sách này lên, RAM giữ tới cùng.
    private let priority: [MetricKind] = [.memory, .cpu, .disk]

    private var timer: Timer?
    private var spaceTimer: Timer?
    private(set) var lastStats = Stats()

    private var shownCount = 3
    private var lastLayoutChange: CFAbsoluteTime = 0
    private var lastGrow: CFAbsoluteTime = -.infinity
    private var nextGrowAllowed: CFAbsoluteTime = 0
    private var growBackoff: CFTimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }

        controllers = [CPUController(), MemoryController(), DiskController()]
        controllers.forEach { $0.build() }
        layoutItems(rebuild: true)

        _ = cpuSampler.sample()
        _ = diskSampler.sample()

        restartTimer()
        let space = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkMenuBarSpace() }
        RunLoop.main.add(space, forMode: .common)
        spaceTimer = space
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.tick() }
        applyDebugArguments()
    }

    // MARK: - Chuyển giữa ba menu

    /// Khi một menu đang mở, cú bấm sang mục khác bị vòng theo dõi của menu nuốt
    /// mất nên mục kia không hề nhận được, phải bấm hai lần. Ở đây bắt lúc menu
    /// vừa đóng, thấy con trỏ đang nằm trên mục nào thì mở menu của mục đó.
    private func itemUnderCursor(excluding skip: MetricController) -> MetricController? {
        guard !NSEvent.modifierFlags.contains(.command) else { return nil }
        let cursor = NSEvent.mouseLocation
        return controllers.first {
            $0 !== skip && ($0.statusItem?.button?.window?.frame.contains(cursor) ?? false)
        }
    }

    func menuOpened() {
        for c in controllers where !c.isOpen { c.statusItem?.button?.highlight(false) }
    }

    func menuClosed(_ closed: MetricController) {
        itemUnderCursor(excluding: closed)?.statusItem?.button?.performClick(nil)
    }

    // MARK: - Nhường chỗ khi thanh menu đầy

    /// Control Center tự chọn mục phải ẩn khi thiếu chỗ và chọn không nhất quán, lúc bỏ
    /// RAM, lúc giữ RAM bỏ hai mục kia. Nên app tự bỏ bớt mục theo thứ tự ưu tiên để
    /// không mục nào của mình bị hệ thống ẩn.
    private func checkMenuBarSpace() {
        let now = CFAbsoluteTimeGetCurrent()
        guard !controllers.contains(where: { $0.isOpen }),
              now - lastLayoutChange > 1.5 else { return }
        let space = MenuBarSpace.read()

        if space.hasOverflow {
            guard shownCount > 1 else { return }
            // Vừa hiện thêm mà tràn ngay thì lần sau đợi lâu gấp đôi mới thử lại.
            growBackoff = now - lastGrow < 8 ? min(growBackoff * 2, 600) : 10
            nextGrowAllowed = now + growBackoff
            shownCount -= 1
            layoutItems(rebuild: false)
            return
        }

        guard shownCount < priority.count, now >= nextGrowAllowed,
              let next = controllers.first(where: { $0.kind == priority[shownCount] })
        else { return }
        let needed = (next.lastWidth > 0 ? next.lastWidth : 80) + 10
        guard space.fits(extraWidth: needed) else { return }
        shownCount += 1
        lastGrow = now
        layoutItems(rebuild: true)
    }

    /// Bật lại một mục đã gỡ thì Control Center chèn nó vào chỗ khác, làm lệch thứ tự
    /// CPU, RAM, ổ đĩa. Nên khi thêm mục phải gỡ hết rồi tạo lại từ phải sang trái.
    private func layoutItems(rebuild: Bool) {
        let shown = Set(priority.prefix(shownCount))
        for c in controllers where rebuild || !shown.contains(c.kind) { c.detach() }
        for c in controllers.reversed() where shown.contains(c.kind) { c.attach() }
        lastLayoutChange = CFAbsoluteTimeGetCurrent()
    }

    @objc private func screensChanged() {
        growBackoff = 10
        nextGrowAllowed = 0
        lastLayoutChange = CFAbsoluteTimeGetCurrent()
    }

    // MARK: - Vòng lấy mẫu

    func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Settings.interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)   // .common để vẫn chạy khi menu đang mở
        timer = t
    }

    private func tick() {
        var s = Stats()
        s.cpu = cpuSampler.sample(
            includeCounts: controllers.contains { $0.kind == .cpu && $0.isOpen })
        s.memory = memorySampler.sample()
        s.disk = diskSampler.sample()
        lastStats = s

        var needsProcesses = false
        for c in controllers {
            c.updateStatusItem(s)
            guard c.isOpen else { continue }
            c.refresh(s)
            if c.wantsProcesses {
                c.refreshProcesses()
                needsProcesses = true
            }
        }
        if needsProcesses { ProcessCache.shared.refresh() }
    }

    // MARK: - Tham số dòng lệnh để kiểm tra giao diện

    private func applyDebugArguments() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let mode = value(after: "--appearance") {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
        }
        if let name = value(after: "--open"),
           let kind = MetricKind(rawValue: name),
           let target = controllers.first(where: { $0.kind == kind }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                target.statusItem?.button?.performClick(nil)
            }
        }
    }
}
