import AppKit

// MARK: - Loại số liệu

enum MetricKind: String {
    case cpu, memory, disk

    var symbol: String {
        switch self {
        case .cpu:    return "cpu"
        case .memory: return "memorychip"
        case .disk:   return "internaldrive"
        }
    }
    var title: String {
        switch self {
        case .cpu:    return "CPU"
        case .memory: return "Bộ nhớ"
        case .disk:   return "Ổ đĩa"
        }
    }
}

struct Stats {
    var cpu = CPUSample()
    var memory = MemorySample()
    var disk = DiskSample()
}

// MARK: - Cài đặt lưu lại

enum Settings {
    private static let key = "refreshInterval"
    static var interval: Double {
        get {
            let v = UserDefaults.standard.double(forKey: key)
            return v > 0 ? v : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Khởi động cùng máy

enum LaunchAtLogin {
    static let label = "local.thuyvv.sysmonitor"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func set(_ enabled: Bool) {
        let uid = getuid()
        if enabled {
            let exe = Bundle.main.executablePath ?? ""
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
                launchctl(["bootout", "gui/\(uid)/\(label)"])
                launchctl(["bootstrap", "gui/\(uid)", plistURL.path])
            }
        } else {
            launchctl(["bootout", "gui/\(uid)/\(label)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}

// MARK: - Lớp nền cho từng mục trên thanh menu

/// Một ô trên thanh menu. Ba ô được tạo một lần lúc mở app và không bao giờ bị gỡ.
///
/// Thanh menu thiếu chỗ thì ô bên trái nhất bị thu độ rộng về 0 và các chỉ số dồn sang
/// phải. Gỡ rồi tạo lại mục thì Control Center giữ mục mới ẩn gần nửa giây làm thanh menu
/// nháy, bật lại bằng isVisible thì mục bị chèn sai chỗ. Ô thu gọn vẫn chiếm lề 16 pt của
/// Control Center, nên để nó ở mép trái cho khe trống lẫn vào khoảng trống sẵn có.
final class StatusSlot {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private(set) weak var metric: MetricController?

    init() {
        guard let b = item.button else { return }
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        b.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    var button: NSStatusBarButton? { item.button }
    var width: CGFloat { item.button?.window?.frame.width ?? 0 }

    func show(_ m: MetricController) {
        guard metric !== m else { return }
        metric = m
        item.length = NSStatusItem.variableLength
        button?.image = m.icon
        button?.title = m.title
        button?.toolTip = m.kind.title
        item.menu = m.menu
    }

    func collapse() {
        guard metric != nil || item.length != 0 else { return }
        metric = nil
        item.menu = nil
        button?.image = nil
        button?.title = ""
        button?.toolTip = nil
        item.length = 0
    }
}

class MetricController: NSObject, NSMenuDelegate {
    let kind: MetricKind
    let menu = NSMenu()
    let header: HeaderView
    let icon: NSImage?
    /// Ô đang hiện chỉ số này, nil khi chỉ số bị bớt vì thanh menu thiếu chỗ.
    weak var slot: StatusSlot?
    private(set) var isOpen = false
    private(set) var title = " --"
    /// Độ rộng thật trên thanh menu lần gần nhất chỉ số này được hiện.
    private(set) var expandedWidth: CGFloat = 80

    private var intervalItems: [NSMenuItem] = []
    private var loginItem: NSMenuItem?

    init(kind: MetricKind) {
        self.kind = kind
        self.header = HeaderView(symbol: kind.symbol, title: kind.title)
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let img = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        self.icon = img
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    // MARK: Dựng menu

    func build() {
        buildBody()
        buildFooter()
    }

    func buildBody() {}
    func refresh(_ s: Stats) {}
    func percent(_ s: Stats) -> Double { 0 }
    var procSort: ProcSort? { nil }
    func applyProcesses(_ list: [ProcInfo]) {}

    final func addView(_ v: NSView) {
        let item = NSMenuItem()
        item.view = v
        menu.addItem(item)
    }

    final func addSeparator() { menu.addItem(.separator()) }

    private func buildFooter() {
        addSeparator()

        let am = NSMenuItem(title: "Mở Activity Monitor…",
                            action: #selector(openActivityMonitor), keyEquivalent: "")
        am.target = self
        menu.addItem(am)

        let speed = NSMenuItem(title: "Tốc độ cập nhật", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in [1.0, 2.0, 3.0, 5.0] {
            let it = NSMenuItem(title: "\(Int(s)) giây",
                                action: #selector(pickInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s
            sub.addItem(it)
            intervalItems.append(it)
        }
        speed.submenu = sub
        menu.addItem(speed)

        let login = NSMenuItem(title: "Khởi động cùng máy",
                               action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login

        addSeparator()
        let quit = NSMenuItem(title: "Thoát SysMonitor",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func syncFooter() {
        for it in intervalItems {
            let v = (it.representedObject as? Double) ?? 0
            it.state = abs(v - Settings.interval) < 0.01 ? .on : .off
        }
        loginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: Hành động

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        Settings.interval = v
        AppDelegate.shared?.restartTimer()
        syncFooter()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        syncFooter()
    }

    // MARK: Cập nhật

    final func updateStatusItem(_ s: Stats) {
        title = " " + Fmt.pct(percent(s))
        guard let slot else { return }
        slot.button?.title = title
        if slot.width >= 30 { expandedWidth = slot.width }
    }

    final func refreshProcesses() {
        guard let sort = procSort else { return }
        let cache = ProcessCache.shared
        applyProcesses(sort == .cpu ? cache.byCPU : cache.byMemory)
    }

    var wantsProcesses: Bool { isOpen && procSort != nil }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        AppDelegate.shared?.menuOpened()
        syncFooter()
        if let s = AppDelegate.shared?.lastStats { refresh(s) }
        if procSort != nil {
            if ProcessCache.shared.isEmpty { ProcessCache.shared.refreshNow() }
            refreshProcesses()
            ProcessCache.shared.refresh(minimumInterval: 0.5)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        // Đóng bằng cancelTracking thì macOS không tự tắt phần tô đậm của nút.
        slot?.button?.highlight(false)
        AppDelegate.shared?.menuClosed(self)
    }
}

// MARK: - CPU

final class CPUController: MetricController {
    private var rowUser, rowSystem, rowIdle: KeyValueRow!
    private var rowLoad, rowTasks, rowUptime: KeyValueRow!
    private var grid: CoreGridView!
    private var procs: ProcessListView!

    init() { super.init(kind: .cpu) }

    override var procSort: ProcSort? { .cpu }
    override func percent(_ s: Stats) -> Double { s.cpu.usage }

    override func buildBody() {
        addView(header)
        addSeparator()
        rowUser = KeyValueRow("Người dùng", accent: .systemBlue)
        rowSystem = KeyValueRow("Hệ thống", accent: .systemRed)
        rowIdle = KeyValueRow("Nhàn rỗi", accent: .systemGray)
        [rowUser, rowSystem, rowIdle].forEach { addView($0!) }

        addSeparator()
        addView(SectionView("Từng nhân"))
        grid = CoreGridView(coreCount: MachineInfo.shared.logicalCores)
        addView(grid)

        addSeparator()
        rowLoad = KeyValueRow("Tải TB (1 · 5 · 15 phút)")
        rowTasks = KeyValueRow("Tiến trình · Luồng")
        rowUptime = KeyValueRow("Máy đã chạy")
        [rowLoad, rowTasks, rowUptime].forEach { addView($0!) }

        addSeparator()
        addView(SectionView("Chiếm CPU nhiều nhất"))
        procs = ProcessListView(rows: 5, tint: .systemBlue)
        addView(procs)
    }

    override func refresh(_ s: Stats) {
        let m = MachineInfo.shared
        var desc = "\(m.cpuBrand) · \(m.logicalCores) nhân"
        if m.performanceCores > 0, m.efficiencyCores > 0 {
            desc = "\(m.cpuBrand) · \(m.performanceCores)P + \(m.efficiencyCores)E"
        }
        header.update(percent: s.cpu.usage, subtitle: desc)
        rowUser.set(Fmt.pct(s.cpu.user))
        rowSystem.set(Fmt.pct(s.cpu.system + s.cpu.nice))
        rowIdle.set(Fmt.pct(s.cpu.idle))
        grid.update(s.cpu.cores)
        rowLoad.set(Fmt.load(s.cpu.loadAverage))
        rowTasks.set("\(s.cpu.processCount) · \(s.cpu.threadCount)")
        rowUptime.set(MachineInfo.shared.bootDate.map { Fmt.uptime(since: $0) } ?? "—")
    }

    override func applyProcesses(_ list: [ProcInfo]) {
        let maxV = max(list.first?.cpu ?? 1, 1)
        procs.update(list.map {
            (name: $0.name, value: String(format: "%.1f%%", $0.cpu), fraction: $0.cpu / maxV)
        })
    }
}

// MARK: - Bộ nhớ

final class MemoryController: MetricController {
    private var rowUsed, rowApp, rowWired, rowCompressed, rowCached, rowFree: KeyValueRow!
    private var rowPressure, rowSwap: KeyValueRow!
    private var procs: ProcessListView!

    init() { super.init(kind: .memory) }

    override var procSort: ProcSort? { .memory }
    override func percent(_ s: Stats) -> Double { s.memory.percent }

    override func buildBody() {
        addView(header)
        addSeparator()
        rowUsed = KeyValueRow("Đã dùng")
        rowApp = KeyValueRow("Ứng dụng", accent: .systemBlue)
        rowWired = KeyValueRow("Hệ thống giữ", accent: .systemRed)
        rowCompressed = KeyValueRow("Đã nén", accent: .systemPurple)
        rowCached = KeyValueRow("Bộ đệm tệp", accent: .systemGray)
        rowFree = KeyValueRow("Còn trống")
        [rowUsed, rowApp, rowWired, rowCompressed, rowCached, rowFree].forEach { addView($0!) }

        addSeparator()
        rowPressure = KeyValueRow("Áp lực bộ nhớ")
        rowSwap = KeyValueRow("Swap đã dùng")
        [rowPressure, rowSwap].forEach { addView($0!) }

        addSeparator()
        addView(SectionView("Chiếm bộ nhớ nhiều nhất"))
        procs = ProcessListView(rows: 5, tint: .systemPurple)
        addView(procs)
    }

    override func refresh(_ s: Stats) {
        let m = s.memory
        header.update(percent: m.percent, subtitle: "Tổng \(Fmt.mem(m.total))")
        rowUsed.set("\(Fmt.mem(m.used)) / \(Fmt.mem(m.total))")
        rowApp.set(Fmt.mem(m.app))
        rowWired.set(Fmt.mem(m.wired))
        rowCompressed.set(Fmt.mem(m.compressed))
        rowCached.set(Fmt.mem(m.cachedFiles))
        rowFree.set(Fmt.mem(m.free))
        let pressureColor: NSColor = m.pressureLevel >= 4 ? .systemRed
                                  : (m.pressureLevel >= 2 ? .systemOrange : .systemGreen)
        rowPressure.set(m.pressureText, color: pressureColor)
        rowSwap.set(m.swapTotal > 0
                    ? "\(Fmt.mem(m.swapUsed)) / \(Fmt.mem(m.swapTotal))"
                    : "Không dùng")
    }

    override func applyProcesses(_ list: [ProcInfo]) {
        let maxV = Double(max(list.first?.rss ?? 1, 1))
        procs.update(list.map {
            (name: $0.name, value: Fmt.mem($0.rss), fraction: Double($0.rss) / maxV)
        })
    }
}

// MARK: - Ổ đĩa

final class DiskController: MetricController {
    private var rowUsed, rowFree, rowTotal: KeyValueRow!
    private var rowRead, rowWrite, rowTotalIO: KeyValueRow!
    private var volumeSection: NSMenuItem!
    private var volumeItems: [(item: NSMenuItem, view: VolumeRowView)] = []
    private let maxVolumes = 4

    init() { super.init(kind: .disk) }

    override func percent(_ s: Stats) -> Double { s.disk.percent }

    override func buildBody() {
        addView(header)
        addSeparator()
        rowUsed = KeyValueRow("Đã dùng")
        rowFree = KeyValueRow("Còn trống")
        rowTotal = KeyValueRow("Tổng dung lượng")
        [rowUsed, rowFree, rowTotal].forEach { addView($0!) }

        addSeparator()
        addView(SectionView("Truy xuất ổ đĩa"))
        rowRead = KeyValueRow("Đang đọc", accent: .systemTeal)
        rowWrite = KeyValueRow("Đang ghi", accent: .systemIndigo)
        rowTotalIO = KeyValueRow("Từ lúc khởi động")
        [rowRead, rowWrite, rowTotalIO].forEach { addView($0!) }

        addSeparator()
        volumeSection = NSMenuItem()
        volumeSection.view = SectionView("Ổ đĩa khác")
        menu.addItem(volumeSection)
        for _ in 0 ..< maxVolumes {
            let v = VolumeRowView()
            let item = NSMenuItem()
            item.view = v
            item.isHidden = true
            menu.addItem(item)
            volumeItems.append((item, v))
        }
        volumeSection.isHidden = true
    }

    override func refresh(_ s: Stats) {
        let d = s.disk
        guard let root = d.root else { return }
        header.update(percent: root.percent, subtitle: "\(root.name) · \(root.fsType)")
        rowUsed.set(Fmt.disk(root.used))
        rowFree.set(Fmt.disk(root.available))
        rowTotal.set(Fmt.disk(root.total))
        rowRead.set(Fmt.rate(d.readRate))
        rowWrite.set(Fmt.rate(d.writeRate))
        rowTotalIO.set("↓ \(Fmt.disk(d.readBytes))  ↑ \(Fmt.disk(d.writeBytes))")

        let others = d.volumes.filter { !$0.isRoot }
        volumeSection.isHidden = others.isEmpty
        for (i, pair) in volumeItems.enumerated() {
            if i < others.count {
                pair.item.isHidden = false
                pair.view.update(others[i])
            } else {
                pair.item.isHidden = true
            }
        }
    }
}
