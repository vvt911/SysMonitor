import AppKit

/// Chỗ trên thanh menu của các màn hình có tai thỏ, đọc từ danh sách cửa sổ hệ thống.
///
/// Trên macOS 26 mọi mục thanh menu do Control Center vẽ, mỗi màn hình một cửa sổ. Mục bị
/// ẩn vì thiếu chỗ vẫn nằm trong danh sách, chỉ bị đánh dấu không hiện, nên đọc được mà
/// không cần quyền ghi màn hình. Chỉ màn có tai thỏ mới biết bề rộng dành cho các mục, là
/// phần bên phải tai thỏ. Màn không tai thỏ thì phần đó tuỳ độ dài menu của app đang mở.
struct MenuBarSpace {
    struct Window {
        let number: Int
        let width: CGFloat
        let visible: Bool
    }

    struct Bar {
        let available: CGFloat
        var windows: [Window] = []
        /// Có mục đang trượt vào hoặc ra, số liệu chưa ổn định.
        var isAnimating = false

        var usedWidth: CGFloat { windows.filter(\.visible).reduce(0) { $0 + $1.width } }
        /// Thanh menu đang bị ẩn, ví dụ khi app chạy toàn màn hình, thì không cửa sổ nào hiện.
        var isShowing: Bool { usedWidth > 0 }
    }

    let bars: [Bar]

    static func read() -> MenuBarSpace {
        let screens = NSScreen.screens
        guard let primaryTop = screens.first?.frame.maxY else { return MenuBarSpace(bars: []) }
        let notched = screens.compactMap { screen in
            screen.auxiliaryTopRightArea.map { (frame: screen.frame, available: $0.width) }
        }
        guard !notched.isEmpty else { return MenuBarSpace(bars: []) }
        var bars = notched.map { Bar(available: $0.available) }

        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  h < 60
            else { continue }

            // Toạ độ CG tính từ góc trên trái màn hình chính, trục y hướng xuống.
            let midX = x + w / 2
            guard let i = notched.firstIndex(where: {
                let top = primaryTop - $0.frame.maxY
                return midX >= $0.frame.minX && midX < $0.frame.maxX && y >= top && y < top + h
            }) else { continue }

            let visible = info[kCGWindowIsOnscreen as String] as? Bool == true
            if y - (primaryTop - notched[i].frame.maxY) >= 1 {
                // Cửa sổ đang ẩn thì hiệu ứng của nó không chiếm chỗ.
                if visible { bars[i].isAnimating = true }
            } else {
                bars[i].windows.append(Window(number: number, width: w, visible: visible))
            }
        }
        return MenuBarSpace(bars: bars)
    }
}
