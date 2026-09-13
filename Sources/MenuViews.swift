import AppKit

// MARK: - Kiểu dáng chung

enum Theme {
    static let width: CGFloat = 300
    static let pad: CGFloat = 14

    static func tint(_ percent: Double) -> NSColor {
        switch percent {
        case ..<0.60: return .systemGreen
        case ..<0.85: return .systemOrange
        default:      return .systemRed
        }
    }

    static func label(_ text: String = "", size: CGFloat = 12,
                      weight: NSFont.Weight = .regular, mono: Bool = false,
                      color: NSColor = .labelColor,
                      align: NSTextAlignment = .left) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                       : .systemFont(ofSize: size, weight: weight)
        tf.textColor = color
        tf.alignment = align
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }
}

/// Gốc toạ độ ở trên cùng cho dễ tính layout.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Thanh tiến độ

final class BarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var fixedTint: NSColor?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()

        let v = min(1, max(0, value))
        guard v > 0.004 else { return }
        let w = max(r.height, r.width * CGFloat(v))
        (fixedTint ?? Theme.tint(v)).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: r.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - Đầu mục

final class HeaderView: FlippedView {
    private let icon = NSImageView()
    private let title = Theme.label(size: 13, weight: .semibold)
    private let subtitle = Theme.label(size: 11, color: .secondaryLabelColor)
    private let percent = Theme.label(size: 23, weight: .medium, mono: true,
                                      align: .right)
    private let bar = BarView()

    init(symbol: String, title titleText: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width, height: 68))
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: titleText)?
            .withSymbolConfiguration(cfg)
        icon.contentTintColor = .labelColor
        icon.frame = NSRect(x: Theme.pad, y: 10, width: 20, height: 20)
        title.stringValue = titleText
        title.frame = NSRect(x: Theme.pad + 26, y: 8, width: 150, height: 16)
        subtitle.frame = NSRect(x: Theme.pad + 26, y: 26, width: 180, height: 14)
        percent.frame = NSRect(x: Theme.width - Theme.pad - 120, y: 6, width: 120, height: 30)
        bar.frame = NSRect(x: Theme.pad, y: 50, width: Theme.width - Theme.pad * 2, height: 6)
        for v in [icon, title, subtitle, percent, bar] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(percent p: Double, subtitle s: String) {
        percent.stringValue = String(format: "%.1f%%", p * 100)
        percent.textColor = Theme.tint(p)
        subtitle.stringValue = s
        bar.value = p
    }
}

// MARK: - Dòng nhãn và giá trị

final class KeyValueRow: FlippedView {
    private let key = Theme.label(size: 12, color: .secondaryLabelColor)
    private let value = Theme.label(size: 12, mono: true, align: .right)
    private var swatch: NSView?

    init(_ keyText: String, accent: NSColor? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width, height: 21))
        var x = Theme.pad
        if let accent {
            let dot = NSView(frame: NSRect(x: x, y: 7, width: 7, height: 7))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = accent.cgColor
            dot.layer?.cornerRadius = 3.5
            addSubview(dot)
            swatch = dot
            x += 13
        }
        key.stringValue = keyText
        key.frame = NSRect(x: x, y: 2, width: 150, height: 16)
        value.frame = NSRect(x: Theme.width - Theme.pad - 160, y: 2, width: 160, height: 16)
        addSubview(key)
        addSubview(value)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, color: NSColor = .labelColor) {
        value.stringValue = text
        value.textColor = color
    }
}

// MARK: - Tiêu đề nhóm

final class SectionView: FlippedView {
    init(_ text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width, height: 24))
        let l = Theme.label(text.uppercased(), size: 10, weight: .semibold,
                            color: .tertiaryLabelColor)
        l.frame = NSRect(x: Theme.pad, y: 8, width: Theme.width - Theme.pad * 2, height: 14)
        addSubview(l)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Lưới từng nhân CPU

final class CoreGridView: FlippedView {
    private var values: [Double] = []
    private var names: [String] = []
    private let columns = 2
    private let rowHeight: CGFloat = 17

    init(coreCount: Int) {
        let e = MachineInfo.shared.efficiencyCores
        let p = MachineInfo.shared.performanceCores
        var labels: [String] = []
        if e + p == coreCount, e > 0, p > 0 {
            // Apple silicon liệt kê nhân tiết kiệm điện trước
            for i in 1...e { labels.append("E\(i)") }
            for i in 1...p { labels.append("P\(i)") }
        } else {
            for i in 1...max(1, coreCount) { labels.append("\(i)") }
        }
        names = labels
        values = [Double](repeating: 0, count: coreCount)
        let rows = (coreCount + columns - 1) / columns
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width,
                                 height: CGFloat(rows) * rowHeight + 4))
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ v: [Double]) {
        guard v.count == values.count else { return }
        values = v
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let cellW = (Theme.width - Theme.pad * 2 - 8) / CGFloat(columns)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor]

        for (i, v) in values.enumerated() {
            let col = i % columns
            let row = i / columns
            let x = Theme.pad + CGFloat(col) * (cellW + 8)
            let y = CGFloat(row) * rowHeight + 2

            (names.indices.contains(i) ? names[i] : "")
                .draw(at: NSPoint(x: x, y: y + 3), withAttributes: nameAttrs)

            let barX = x + 20
            let barW = cellW - 20 - 30
            let track = NSRect(x: barX, y: y + 5, width: barW, height: 5)
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
            let f = min(1, max(0, v))
            if f > 0.01 {
                Theme.tint(f).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: y + 5,
                                                 width: max(5, barW * CGFloat(f)), height: 5),
                             xRadius: 2.5, yRadius: 2.5).fill()
            }
            let text = String(format: "%3.0f%%", f * 100) as NSString
            text.draw(in: NSRect(x: x + cellW - 28, y: y + 3, width: 28, height: 12),
                      withAttributes: valAttrs)
        }
    }
}

// MARK: - Danh sách tiến trình

final class ProcessListView: FlippedView {
    private var items: [(name: String, value: String, fraction: Double)] = []
    private let rowHeight: CGFloat = 19
    private let capacity: Int
    private let tint: NSColor

    init(rows: Int, tint: NSColor) {
        capacity = rows
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width,
                                 height: CGFloat(rows) * rowHeight + 2))
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ new: [(name: String, value: String, fraction: Double)]) {
        items = Array(new.prefix(capacity))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let nameStyle = NSMutableParagraphStyle()
        nameStyle.lineBreakMode = .byTruncatingTail
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: nameStyle]
        let valStyle = NSMutableParagraphStyle()
        valStyle.alignment = .right
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: valStyle]

        for (i, item) in items.enumerated() {
            let y = CGFloat(i) * rowHeight
            let barW = (Theme.width - Theme.pad * 2) * CGFloat(min(1, max(0, item.fraction)))
            if barW > 1 {
                tint.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: NSRect(x: Theme.pad, y: y + 1,
                                                 width: max(3, barW), height: rowHeight - 3),
                             xRadius: 3, yRadius: 3).fill()
            }
            (item.name as NSString).draw(
                in: NSRect(x: Theme.pad + 5, y: y + 3, width: Theme.width - Theme.pad * 2 - 80, height: 15),
                withAttributes: nameAttrs)
            (item.value as NSString).draw(
                in: NSRect(x: Theme.width - Theme.pad - 75, y: y + 3.5, width: 70, height: 14),
                withAttributes: valAttrs)
        }
    }
}

// MARK: - Dòng cho từng ổ đĩa

final class VolumeRowView: FlippedView {
    private let name = Theme.label(size: 11.5)
    private let detail = Theme.label(size: 10, mono: true, color: .secondaryLabelColor, align: .right)
    private let bar = BarView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.width, height: 34))
        name.frame = NSRect(x: Theme.pad, y: 1, width: 150, height: 15)
        detail.frame = NSRect(x: Theme.width - Theme.pad - 150, y: 2, width: 150, height: 14)
        bar.frame = NSRect(x: Theme.pad, y: 20, width: Theme.width - Theme.pad * 2, height: 5)
        for v in [name, detail, bar] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ v: VolumeInfo) {
        name.stringValue = v.name
        detail.stringValue = "\(Fmt.disk(v.used)) / \(Fmt.disk(v.total))  ·  \(Fmt.pct(v.percent))"
        bar.value = v.percent
    }
}
