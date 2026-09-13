import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()

    private var controllers: [MetricController] = []
    private var timer: Timer?
    private(set) var lastStats = Stats()

    private var hoverPoller: Timer?
    private var hoverTarget: MetricController?
    private var hoverSince: CFAbsoluteTime = 0
    private var pendingSwitch: MetricController?
    private let hoverDelay: CFTimeInterval = 0.12

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }

        // NSStatusBar chèn mục mới vào bên trái nên phải tạo theo thứ tự ngược,
        // để trên thanh menu đọc từ trái sang là CPU, bộ nhớ, ổ đĩa.
        let disk = DiskController()
        let memory = MemoryController()
        let cpu = CPUController()
        controllers = [cpu, memory, disk]
        controllers.forEach { $0.build() }

        _ = cpuSampler.sample()
        _ = diskSampler.sample()

        restartTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.tick() }
        applyDebugArguments()
    }

    // MARK: - Chuyển giữa ba menu

    private func itemUnderCursor(excluding skip: MetricController) -> MetricController? {
        guard !NSEvent.modifierFlags.contains(.command) else { return nil }
        let cursor = NSEvent.mouseLocation
        return controllers.first {
            $0 !== skip && ($0.statusItem.button?.window?.frame.contains(cursor) ?? false)
        }
    }

    /// Khi một menu đang mở, cú bấm sang mục khác bị vòng theo dõi của menu nuốt
    /// mất, và macOS mất khoảng 270 ms mới đóng menu cũ, không rút ngắn được.
    /// Ngược lại tự gọi huỷ chỉ tốn 5 ms, nên menu chuyển theo con trỏ giống hệt
    /// cách các menu Apple, File, Edit hoạt động, khỏi phải bấm.
    private func pollHover() {
        guard pendingSwitch == nil,
              let open = controllers.first(where: { $0.isOpen }),
              let target = itemUnderCursor(excluding: open)
        else {
            hoverTarget = nil
            return
        }
        guard target === hoverTarget else {
            hoverTarget = target
            hoverSince = CFAbsoluteTimeGetCurrent()
            return
        }
        guard CFAbsoluteTimeGetCurrent() - hoverSince >= hoverDelay else { return }

        hoverTarget = nil
        pendingSwitch = target
        open.menu.cancelTrackingWithoutAnimation()
    }

    func menuOpened() {
        for c in controllers where !c.isOpen { c.statusItem.button?.highlight(false) }
        guard hoverPoller == nil else { return }
        let t = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.pollHover() }
        RunLoop.main.add(t, forMode: .common)
        hoverPoller = t
    }

    func menuClosed(_ closed: MetricController) {
        if let target = pendingSwitch {
            pendingSwitch = nil
            // Gọi thẳng tại đây sẽ lồng menu mới vào trong callback của Timer,
            // phải đợi vòng theo dõi của menu cũ thoát hẳn.
            DispatchQueue.main.async { target.statusItem.button?.performClick(nil) }
            return
        }
        hoverPoller?.invalidate()
        hoverPoller = nil
        hoverTarget = nil

        itemUnderCursor(excluding: closed)?.statusItem.button?.performClick(nil)
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
                target.statusItem.button?.performClick(nil)
            }
        }
    }
}
