import AppKit

/// Chỗ trên thanh menu của từng màn hình, đọc từ danh sách cửa sổ hệ thống.
///
/// Trên macOS 26 mọi mục thanh menu do Control Center vẽ, mỗi màn hình một cửa sổ.
/// Cửa sổ phía app chỉ nằm trên một màn hình và luôn báo đang hiện nên không dùng được.
/// Mục bị ẩn vì thiếu chỗ vẫn có trong danh sách nhưng bị đánh dấu không nằm trên màn
/// hình, và đọc thông tin này không cần quyền ghi màn hình.
struct MenuBarSpace {
    struct Bar {
        var hiddenCount = 0
        var usedWidth: CGFloat = 0
        /// Chỉ biết được trên màn có tai thỏ: phần thanh menu bên phải tai thỏ.
        var available: CGFloat?

        /// Thanh menu đang bị ẩn, ví dụ khi app chạy toàn màn hình, thì mọi cửa sổ đều
        /// ngoài màn hình. Trường hợp đó không phải thiếu chỗ.
        var isShowing: Bool { usedWidth > 0 }
    }

    let bars: [Bar]

    var hasOverflow: Bool { bars.contains { $0.isShowing && $0.hiddenCount > 0 } }

    /// Màn nào không biết bề rộng dùng được thì coi như đủ chỗ.
    func fits(extraWidth: CGFloat) -> Bool {
        bars.allSatisfy { bar in
            guard bar.isShowing, let available = bar.available else { return true }
            return available - bar.usedWidth >= extraWidth
        }
    }

    static func read() -> MenuBarSpace {
        let screens = NSScreen.screens
        guard let primaryTop = screens.first?.frame.maxY else { return MenuBarSpace(bars: []) }
        var bars = screens.map { Bar(available: $0.auxiliaryTopRightArea?.width) }

        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        for info in windows {
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  h < 60
            else { continue }

            // Toạ độ CG tính từ góc trên trái màn hình chính, trục y hướng xuống.
            let midX = x + w / 2
            let sameTop = screens.indices.filter { abs(primaryTop - screens[$0].frame.maxY - y) < 1 }
            guard let i = sameTop.min(by: {
                distance(midX, screens[$0].frame) < distance(midX, screens[$1].frame)
            }) else { continue }

            if info[kCGWindowIsOnscreen as String] as? Bool == true {
                bars[i].usedWidth += w
            } else {
                bars[i].hiddenCount += 1
            }
        }
        return MenuBarSpace(bars: bars)
    }

    private static func distance(_ x: CGFloat, _ frame: NSRect) -> CGFloat {
        x < frame.minX ? frame.minX - x : max(0, x - frame.maxX)
    }
}
