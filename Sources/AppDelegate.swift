import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    private static let showSettingsNotification = Notification.Name("local.thuyvv.sysmonitor.showSettings")

    private let settings = AppSettings.shared
    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()

    private var controllers: [MetricController] = []
    /// Ba ô trên thanh menu, từ trái sang phải.
    private var slots: [StatusSlot] = []
    private var settingsWindow: SettingsWindowController?

    private var timer: Timer?
    private var spaceTimer: Timer?
    private(set) var lastStats = Stats()

    private var shownCount = 0
    private var pendingGrowTarget: Int?
    private var watchUntil: CFAbsoluteTime = 0
    private var lastSpaceRead: CFAbsoluteTime = 0
    private var ghostCandidates: [Int: CFAbsoluteTime] = [:]
    private var ghosts: Set<Int> = []
    private let growMargin: CGFloat = 10
    /// Lề Control Center giữ lại cho một ô đã thu độ rộng về 0.
    private let collapsedWidth: CGFloat = 16
    /// Control Center xếp các mục thưa hơn phép cộng độ rộng vài point.
    private let packingSlack: CGFloat = 4

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.contains(where: { $0.processIdentifier != me }) {
            // Mở app lần nữa khi đang chạy thì bản đang chạy hiện cửa sổ Cài đặt.
            DistributedNotificationCenter.default().postNotificationName(
                Self.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettings), name: Self.showSettingsNotification, object: nil)

        controllers = [CPUController(), MemoryController(), DiskController()]
        controllers.forEach { $0.build() }
        // NSStatusBar chèn mục mới vào bên trái nên ô tạo trước nằm bên phải. Bật isVisible
        // ngay sau khi tạo từng ô, phòng macOS khôi phục trạng thái ẩn của lần chạy trước.
        slots = controllers.map { _ in
            let slot = StatusSlot()
            slot.item.isVisible = true
            return slot
        }.reversed()
        apply(enabledMetrics.count)

        settings.onChange = { [weak self] change in self?.settingsChanged(change) }

        _ = cpuSampler.sample()
        _ = diskSampler.sample()

        restartTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.tick()
            self?.startSpaceWatch()
        }
        applyDebugArguments()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Cài đặt

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
                self?.lastStats.disk.volumes ?? []
            }
        }
        settingsWindow?.present()
    }

    /// Chỉ số đang bật, theo thứ tự từ trái sang phải.
    private var enabledMetrics: [MetricController] {
        settings.displayOrder
            .filter { settings.enabled.contains($0) }
            .compactMap { kind in controllers.first { $0.kind == kind } }
    }

    private var enabledPriority: [MetricKind] {
        settings.priority.filter { settings.enabled.contains($0) }
    }

    private func settingsChanged(_ change: AppSettings.Change) {
        switch change {
        case .timer:
            restartTimer()
        case .menuBar:
            slots.forEach { $0.render() }
        case .layout:
            controllers.forEach { $0.updateStatusItem(lastStats) }
            apply(enabledMetrics.count)
        case .menus:
            guard !controllers.contains(where: \.isOpen) else { return }
            controllers.forEach { $0.build() }
            slots.forEach { $0.render() }
            settingsWindow?.updateTitle()
        }
    }

    // MARK: - Chuyển giữa ba menu

    /// Khi một menu đang mở, cú bấm sang mục khác bị vòng theo dõi của menu nuốt
    /// mất nên mục kia không hề nhận được, phải bấm hai lần. Ở đây bắt lúc menu
    /// vừa đóng, thấy con trỏ đang nằm trên mục nào thì mở menu của mục đó.
    private func itemUnderCursor(excluding skip: MetricController) -> MetricController? {
        guard !NSEvent.modifierFlags.contains(.command) else { return nil }
        let cursor = NSEvent.mouseLocation
        return controllers.first {
            $0 !== skip && ($0.slot?.button?.window?.frame.contains(cursor) ?? false)
        }
    }

    func menuOpened() {
        for slot in slots where slot.metric?.isOpen != true { slot.button?.highlight(false) }
    }

    func menuClosed(_ closed: MetricController) {
        itemUnderCursor(excluding: closed)?.slot?.button?.performClick(nil)
    }

    // MARK: - Nhường chỗ khi thanh menu đầy

    /// Control Center tự chọn mục phải ẩn khi thiếu chỗ và chọn không nhất quán, lúc ẩn
    /// RAM, lúc giữ RAM ẩn hai mục kia. Nên app tự tính số chỉ số vừa chỗ theo thứ tự ưu
    /// tiên rồi đổi một lần, không để ô nào của mình bị hệ thống ẩn.
    private func startSpaceWatch() {
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.spaceTimerFired() }
        RunLoop.main.add(t, forMode: .common)
        spaceTimer = t

        // Thanh menu đổi thì Control Center dời hoặc ẩn các ô của app, và cửa sổ phía app
        // được báo gần như tức thì. App mở hay thoát cũng hay thêm bớt biểu tượng.
        let center = NotificationCenter.default
        for slot in slots {
            guard let window = slot.button?.window else { continue }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                center.addObserver(self, selector: #selector(menuBarMayHaveChanged), name: name, object: window)
            }
        }
        center.addObserver(self, selector: #selector(menuBarMayHaveChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(menuBarMayHaveChanged), name: name, object: nil)
        }
        menuBarMayHaveChanged()
    }

    /// Có dấu hiệu thanh menu vừa đổi thì đọc dày trong chốc lát, bình thường mỗi giây một lần.
    @objc private func menuBarMayHaveChanged() {
        watchUntil = CFAbsoluteTimeGetCurrent() + 1.5
    }

    private func spaceTimerFired() {
        let now = CFAbsoluteTimeGetCurrent()
        guard settings.autoFit,
              now < watchUntil || now - lastSpaceRead >= 1,
              !controllers.contains(where: { $0.isOpen }) else { return }
        lastSpaceRead = now
        evaluateSpace(at: now)
    }

    private func evaluateSpace(at now: CFAbsoluteTime) {
        let all = MenuBarSpace.read().bars
        guard all.contains(where: { !$0.windows.isEmpty }) else {
            if shownCount < enabledMetrics.count { apply(enabledMetrics.count) }
            return
        }
        let bars = all.filter(\.isShowing)
        let hiddenNow = Set(bars.flatMap { $0.windows.filter { !$0.visible }.map(\.number) })
        ghosts.formIntersection(hiddenNow)
        ghostCandidates = ghostCandidates.filter { hiddenNow.contains($0.key) }

        guard !bars.isEmpty else { pendingGrowTarget = nil; return }
        if bars.contains(where: \.isAnimating) { menuBarMayHaveChanged(); return }

        let target = bars.map { fittingCount(on: $0, at: now) }.min() ?? shownCount
        if target < shownCount {
            // Thiếu chỗ thì bớt ngay, chậm lúc nào là chỉ số ưu tiên cao bị ẩn lúc đó.
            apply(target)
        } else if target > shownCount {
            // Thêm thì đợi hai lần đọc liền nhau cùng kết quả, tránh nhảy qua nhảy lại.
            if pendingGrowTarget == target {
                apply(target)
            } else {
                pendingGrowTarget = target
                menuBarMayHaveChanged()
            }
        } else {
            pendingGrowTarget = nil
        }
    }

    /// Số chỉ số nhiều nhất theo thứ tự ưu tiên mà thanh menu này chứa được.
    private func fittingCount(on bar: MenuBarSpace.Bar, at now: CFAbsoluteTime) -> Int {
        let ourWidths = slots.filter { $0.item.isVisible }.map(\.width)
        let free = bar.available - bar.usedWidth
        var hiddenForLackOfSpace: CGFloat = 0
        for window in bar.windows where !window.visible && !ghosts.contains(window.number) {
            // Ô của app bị ẩn thì luôn tính, kể cả khi về số học là vừa chỗ, vì Control
            // Center có lúc vẫn giữ ẩn. Bỏ sót chỗ này làm chỉ số bật tắt liên tục.
            let isOurs = ourWidths.contains { abs($0 - window.width) < 0.5 }
            if isOurs || window.width + packingSlack > free {
                hiddenForLackOfSpace += window.width
                continue
            }
            // Mục của app khác vừa chỗ mà vẫn bị ẩn quá 1 giây là cửa sổ ma, sót lại khi
            // app đó thoát, từ đó bỏ qua.
            let since = ghostCandidates[window.number] ?? now
            ghostCandidates[window.number] = since
            if now - since >= 1 { ghosts.insert(window.number) }
        }

        let metrics = enabledMetrics
        let order = enabledPriority
        let others = bar.usedWidth + hiddenForLackOfSpace - ourWidths.reduce(0, +)
        var count = metrics.count
        while count > 1 {
            let shown = Set(order.prefix(count))
            let needed = metrics.reduce(others) { sum, c in
                sum + (shown.contains(c.kind) ? c.expandedWidth : collapsedWidth)
            }
            if needed + (count > shownCount ? growMargin : 0) <= bar.available { break }
            count -= 1
        }
        return count
    }

    /// Chỉ số được hiện dồn vào những ô bên phải, giữ thứ tự từ trái sang phải trong Cài đặt.
    private func apply(_ requested: Int) {
        let metrics = enabledMetrics
        let target = min(max(requested, 1), metrics.count)
        pendingGrowTarget = nil
        shownCount = target
        let shownKinds = Set(enabledPriority.prefix(target))
        let shown = metrics.filter { shownKinds.contains($0.kind) }
        let firstEnabled = slots.count - metrics.count
        let firstShown = slots.count - shown.count
        for (index, slot) in slots.enumerated() {
            if index < firstShown { slot.collapse() } else { slot.show(shown[index - firstShown]) }
            // Chỉ số bị tắt trong Cài đặt thì ẩn hẳn ô, không để lại khe 16 pt. Các ô này luôn
            // nằm bên trái, nên bật lại thì mục xuất hiện ở mép trái vẫn đúng chỗ.
            let visible = index >= firstEnabled
            if slot.item.isVisible != visible { slot.item.isVisible = visible }
        }
        for c in controllers { c.slot = slots.first { $0.metric === c } }
        menuBarMayHaveChanged()
    }

    // MARK: - Vòng lấy mẫu

    func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
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
                target.slot?.button?.performClick(nil)
            }
        }
        if args.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showSettings() }
        }
    }
}
