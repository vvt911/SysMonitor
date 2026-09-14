import Combine
import Foundation

// MARK: - Ngôn ngữ

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    /// Tên tiếng Việt và tiếng Anh viết bằng chính ngôn ngữ đó để ai cũng nhận ra.
    var displayName: String {
        switch self {
        case .system:     return tr("Theo hệ thống", "System default")
        case .vietnamese: return "Tiếng Việt"
        case .english:    return "English"
        }
    }
}

/// Chuỗi hiển thị theo ngôn ngữ đang chọn. App ít chuỗi nên viết cả hai bản ngay chỗ dùng
/// thay vì tách bảng dịch.
func tr(_ vietnamese: String, _ english: String) -> String {
    AppSettings.shared.usesVietnamese ? vietnamese : english
}

// MARK: - Cài đặt

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Change { case timer, menuBar, layout, menus }

    /// App đăng ký để áp dụng ngay khi người dùng đổi một cài đặt.
    var onChange: ((Change) -> Void)?

    @Published var language: AppLanguage {
        didSet { store(language.rawValue, "language"); onChange?(.menus) }
    }
    @Published var refreshInterval: Double {
        didSet { store(refreshInterval, "refreshInterval"); onChange?(.timer) }
    }
    /// Thứ tự từ trái sang phải trên thanh menu.
    @Published var displayOrder: [MetricKind] {
        didSet { store(displayOrder.map(\.rawValue), "displayOrder"); onChange?(.layout) }
    }
    @Published var enabled: Set<MetricKind> {
        didSet { store(enabled.map(\.rawValue), "enabledMetrics"); onChange?(.layout) }
    }
    @Published var showIcons: Bool {
        didSet { store(showIcons, "showIcons"); onChange?(.menuBar) }
    }
    @Published var decimals: Int {
        didSet { store(decimals, "decimals"); onChange?(.menuBar) }
    }
    @Published var colorMenuBar: Bool {
        didSet { store(colorMenuBar, "colorMenuBar"); onChange?(.menuBar) }
    }
    /// Đường dẫn ổ đĩa hiện trên thanh menu, rỗng là ổ khởi động.
    @Published var diskVolumePath: String {
        didSet { store(diskVolumePath, "diskVolumePath"); onChange?(.layout) }
    }
    @Published var autoFit: Bool {
        didSet { store(autoFit, "autoFit"); onChange?(.layout) }
    }
    /// Thanh menu thiếu chỗ thì bớt từ cuối danh sách này lên.
    @Published var priority: [MetricKind] {
        didSet { store(priority.map(\.rawValue), "priority"); onChange?(.layout) }
    }
    @Published var processRows: Int {
        didSet { store(processRows, "processRows"); onChange?(.menus) }
    }
    @Published var warningPercent: Int {
        didSet {
            if criticalPercent < warningPercent + 5 { criticalPercent = min(95, warningPercent + 5) }
            store(warningPercent, "warningPercent")
            onChange?(.menuBar)
        }
    }
    @Published var criticalPercent: Int {
        didSet {
            if warningPercent > criticalPercent - 5 { warningPercent = max(30, criticalPercent - 5) }
            store(criticalPercent, "criticalPercent")
            onChange?(.menuBar)
        }
    }

    var warningLevel: Double { Double(warningPercent) / 100 }
    var criticalLevel: Double { Double(criticalPercent) / 100 }

    var usesVietnamese: Bool {
        switch language {
        case .vietnamese: return true
        case .english:    return false
        case .system:     return Locale.preferredLanguages.first?.hasPrefix("vi") ?? false
        }
    }

    private init() {
        let d = UserDefaults.standard
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .vietnamese
        let interval = d.double(forKey: "refreshInterval")
        refreshInterval = [1.0, 2.0, 3.0, 5.0].contains(interval) ? interval : 1
        displayOrder = Self.ordering(d.stringArray(forKey: "displayOrder"), fallback: [.cpu, .memory, .disk])
        let stored = Set((d.stringArray(forKey: "enabledMetrics") ?? []).compactMap(MetricKind.init(rawValue:)))
        enabled = stored.isEmpty ? Set(MetricKind.allCases) : stored
        showIcons = d.object(forKey: "showIcons") as? Bool ?? true
        decimals = min(max(d.object(forKey: "decimals") as? Int ?? 1, 0), 1)
        colorMenuBar = d.object(forKey: "colorMenuBar") as? Bool ?? false
        diskVolumePath = d.string(forKey: "diskVolumePath") ?? ""
        autoFit = d.object(forKey: "autoFit") as? Bool ?? true
        priority = Self.ordering(d.stringArray(forKey: "priority"), fallback: [.memory, .cpu, .disk])
        let rows = d.object(forKey: "processRows") as? Int ?? 5
        processRows = [3, 5, 8].contains(rows) ? rows : 5
        let warning = min(max(d.object(forKey: "warningPercent") as? Int ?? 60, 30), 90)
        warningPercent = warning
        criticalPercent = min(max(d.object(forKey: "criticalPercent") as? Int ?? 85, warning + 5), 95)
    }

    /// Luôn giữ ít nhất một chỉ số, không thì app mất chỗ bấm trên thanh menu.
    func setEnabled(_ kind: MetricKind, _ on: Bool) {
        var set = enabled
        if on { set.insert(kind) } else if set.count > 1 { set.remove(kind) }
        if set != enabled { enabled = set }
    }

    func move(_ kind: MetricKind, by offset: Int,
              in keyPath: ReferenceWritableKeyPath<AppSettings, [MetricKind]>) {
        var list = self[keyPath: keyPath]
        guard let i = list.firstIndex(of: kind), list.indices.contains(i + offset) else { return }
        list.swapAt(i, i + offset)
        self[keyPath: keyPath] = list
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func ordering(_ raw: [String]?, fallback: [MetricKind]) -> [MetricKind] {
        let list = (raw ?? []).compactMap(MetricKind.init(rawValue:))
        let complete = list.count == MetricKind.allCases.count && Set(list).count == list.count
        return complete ? list : fallback
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
