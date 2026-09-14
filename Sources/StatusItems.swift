import AppKit

// MARK: - Loại số liệu

enum MetricKind: String, CaseIterable {
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
        case .memory: return tr("Bộ nhớ", "Memory")
        case .disk:   return tr("Ổ đĩa", "Disk")
        }
    }
}

struct Stats {
    var cpu = CPUSample()
    var memory = MemorySample()
    var disk = DiskSample()
}

// MARK: - Ô trên thanh menu

/// Một ô trên thanh menu. Ba ô được tạo một lần lúc mở app và không bao giờ bị gỡ.
///
/// Thanh menu thiếu chỗ thì ô bên trái nhất bị thu độ rộng về 0 và các chỉ số dồn sang
/// phải. Gỡ rồi tạo lại mục thì Control Center giữ mục mới ẩn gần nửa giây làm thanh menu
/// nháy, bật lại bằng isVisible thì mục bị chèn sang mép trái. Ô thu gọn vẫn chiếm lề 16 pt
/// của Control Center, nên để nó ở mép trái cho khe trống lẫn vào khoảng trống sẵn có.
final class StatusSlot {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private(set) weak var metric: MetricController?

    init() {
        guard let b = item.button else { return }
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        b.font = Self.font
    }

    var button: NSStatusBarButton? { item.button }
    var width: CGFloat { item.button?.window?.frame.width ?? 0 }

    func show(_ m: MetricController) {
        guard metric !== m else { return render() }
        metric = m
        item.length = NSStatusItem.variableLength
        item.menu = m.menu
        render()
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

    /// Vẽ lại nội dung theo số liệu và cài đặt hiện tại.
    func render() {
        guard let m = metric, let b = button else { return }
        let settings = AppSettings.shared
        b.image = settings.showIcons ? m.icon : nil
        b.toolTip = m.kind.title
        let text = (settings.showIcons ? " " : "") + (m.value.map(Fmt.menuBarPercent) ?? "--")
        if settings.colorMenuBar, let v = m.value, v >= settings.warningLevel {
            b.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: Self.font, .foregroundColor: Theme.tint(v)])
        } else {
            b.title = text
        }
    }
}

// MARK: - Lớp nền cho từng chỉ số

class MetricController: NSObject, NSMenuDelegate {
    let kind: MetricKind
    let menu = NSMenu()
    let icon: NSImage?
    private(set) var header: HeaderView!
    /// Ô đang hiện chỉ số này, nil khi chỉ số bị bớt hoặc bị tắt.
    weak var slot: StatusSlot?
    private(set) var isOpen = false
    /// Giá trị 0...1 của lần lấy mẫu gần nhất, nil khi chưa có.
    private(set) var value: Double?
    /// Độ rộng thật trên thanh menu lần gần nhất chỉ số này được hiện.
    private(set) var expandedWidth: CGFloat = 80

    init(kind: MetricKind) {
        self.kind = kind
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

    /// Dựng lại toàn bộ menu, gọi lại khi đổi ngôn ngữ hoặc số tiến trình liệt kê.
    func build() {
        menu.removeAllItems()
        header = HeaderView(symbol: kind.symbol, title: kind.title)
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
        addAction(tr("Mở Activity Monitor…", "Open Activity Monitor…"), #selector(openActivityMonitor))
        addAction(tr("Cài đặt…", "Settings…"), #selector(openSettings), key: ",")
        addSeparator()
        menu.addItem(NSMenuItem(title: tr("Thoát SysMonitor", "Quit SysMonitor"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addAction(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: Hành động

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    @objc private func openSettings() {
        AppDelegate.shared?.showSettings()
    }

    // MARK: Cập nhật

    final func updateStatusItem(_ s: Stats) {
        value = percent(s)
        guard let slot else { return }
        slot.render()
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
        rowUser = KeyValueRow(tr("Người dùng", "User"), accent: .systemBlue)
        rowSystem = KeyValueRow(tr("Hệ thống", "System"), accent: .systemRed)
        rowIdle = KeyValueRow(tr("Nhàn rỗi", "Idle"), accent: .systemGray)
        [rowUser, rowSystem, rowIdle].forEach { addView($0!) }

        addSeparator()
        addView(SectionView(tr("Từng nhân", "Per core")))
        grid = CoreGridView(coreCount: MachineInfo.shared.logicalCores)
        addView(grid)

        addSeparator()
        rowLoad = KeyValueRow(tr("Tải TB (1 · 5 · 15 phút)", "Load average (1 · 5 · 15 min)"))
        rowTasks = KeyValueRow(tr("Tiến trình · Luồng", "Processes · Threads"))
        rowUptime = KeyValueRow(tr("Máy đã chạy", "Uptime"))
        [rowLoad, rowTasks, rowUptime].forEach { addView($0!) }

        addSeparator()
        addView(SectionView(tr("Chiếm CPU nhiều nhất", "Top CPU")))
        procs = ProcessListView(rows: AppSettings.shared.processRows, tint: .systemBlue)
        addView(procs)
    }

    override func refresh(_ s: Stats) {
        let m = MachineInfo.shared
        var desc = "\(m.cpuBrand) · " + tr("\(m.logicalCores) nhân", "\(m.logicalCores) cores")
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
        rowUsed = KeyValueRow(tr("Đã dùng", "Used"))
        rowApp = KeyValueRow(tr("Ứng dụng", "App memory"), accent: .systemBlue)
        rowWired = KeyValueRow(tr("Hệ thống giữ", "Wired"), accent: .systemRed)
        rowCompressed = KeyValueRow(tr("Đã nén", "Compressed"), accent: .systemPurple)
        rowCached = KeyValueRow(tr("Bộ đệm tệp", "Cached files"), accent: .systemGray)
        rowFree = KeyValueRow(tr("Còn trống", "Free"))
        [rowUsed, rowApp, rowWired, rowCompressed, rowCached, rowFree].forEach { addView($0!) }

        addSeparator()
        rowPressure = KeyValueRow(tr("Áp lực bộ nhớ", "Memory pressure"))
        rowSwap = KeyValueRow(tr("Swap đã dùng", "Swap used"))
        [rowPressure, rowSwap].forEach { addView($0!) }

        addSeparator()
        addView(SectionView(tr("Chiếm bộ nhớ nhiều nhất", "Top memory")))
        procs = ProcessListView(rows: AppSettings.shared.processRows, tint: .systemPurple)
        addView(procs)
    }

    override func refresh(_ s: Stats) {
        let m = s.memory
        header.update(percent: m.percent, subtitle: tr("Tổng", "Total") + " \(Fmt.mem(m.total))")
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
                    : tr("Không dùng", "Not in use"))
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

    override func percent(_ s: Stats) -> Double {
        s.disk.volume(at: AppSettings.shared.diskVolumePath)?.percent ?? 0
    }

    override func buildBody() {
        volumeItems = []
        addView(header)
        addSeparator()
        rowUsed = KeyValueRow(tr("Đã dùng", "Used"))
        rowFree = KeyValueRow(tr("Còn trống", "Available"))
        rowTotal = KeyValueRow(tr("Tổng dung lượng", "Capacity"))
        [rowUsed, rowFree, rowTotal].forEach { addView($0!) }

        addSeparator()
        addView(SectionView(tr("Truy xuất ổ đĩa", "Disk activity")))
        rowRead = KeyValueRow(tr("Đang đọc", "Reading"), accent: .systemTeal)
        rowWrite = KeyValueRow(tr("Đang ghi", "Writing"), accent: .systemIndigo)
        rowTotalIO = KeyValueRow(tr("Từ lúc khởi động", "Since boot"))
        [rowRead, rowWrite, rowTotalIO].forEach { addView($0!) }

        addSeparator()
        volumeSection = NSMenuItem()
        volumeSection.view = SectionView(tr("Ổ đĩa khác", "Other volumes"))
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
        guard let shown = d.volume(at: AppSettings.shared.diskVolumePath) else { return }
        header.update(percent: shown.percent, subtitle: "\(shown.name) · \(shown.fsType)")
        rowUsed.set(Fmt.disk(shown.used))
        rowFree.set(Fmt.disk(shown.available))
        rowTotal.set(Fmt.disk(shown.total))
        rowRead.set(Fmt.rate(d.readRate))
        rowWrite.set(Fmt.rate(d.writeRate))
        rowTotalIO.set("↓ \(Fmt.disk(d.readBytes))  ↑ \(Fmt.disk(d.writeBytes))")

        let others = d.volumes.filter { $0.path != shown.path }
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
