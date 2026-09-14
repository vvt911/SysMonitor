import Foundation

enum Fmt {
    private static let memFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory          // cơ số 1024, như Activity Monitor
        f.allowedUnits = [.useGB, .useMB]
        return f
    }()

    private static let diskFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file            // cơ số 1000, như Finder
        f.allowedUnits = [.useGB, .useTB, .useMB]
        return f
    }()

    static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    /// Con số trên thanh menu, số chữ số thập phân theo Cài đặt.
    static func menuBarPercent(_ v: Double) -> String {
        String(format: AppSettings.shared.decimals == 0 ? "%.0f%%" : "%.1f%%", v * 100)
    }
    static func mem(_ bytes: UInt64) -> String { memFormatter.string(fromByteCount: Int64(bytes)) }
    static func disk(_ bytes: UInt64) -> String { diskFormatter.string(fromByteCount: Int64(bytes)) }

    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1_000 { return String(format: "%.0f B/s", v) }
        if v < 1_000_000 { return String(format: "%.0f KB/s", v / 1_000) }
        if v < 1_000_000_000 { return String(format: "%.1f MB/s", v / 1_000_000) }
        return String(format: "%.2f GB/s", v / 1_000_000_000)
    }

    /// "12 ngày 4 giờ", "4 giờ 21 phút" hoặc bản tiếng Anh ngắn gọn.
    static func uptime(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        let days = s / 86_400
        let hours = (s % 86_400) / 3_600
        let minutes = (s % 3_600) / 60
        if days > 0 { return tr("\(days) ngày \(hours) giờ", "\(days)d \(hours)h") }
        if hours > 0 { return tr("\(hours) giờ \(minutes) phút", "\(hours)h \(minutes)m") }
        return tr("\(minutes) phút", "\(minutes) min")
    }

    static func load(_ l: (Double, Double, Double)) -> String {
        String(format: "%.2f · %.2f · %.2f", l.0, l.1, l.2)
    }
}
