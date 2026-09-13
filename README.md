# SysMonitor

App nhỏ nằm trên thanh menu macOS, hiện ba chỉ số CPU, bộ nhớ và ổ đĩa.
Bấm vào từng chỉ số để xem bảng chi tiết.

```
🔲 11.0%    ▭ 75.5%    ⬭ 74.0%
```

## Cài đặt

```bash
./build.sh
```

Script dựng `~/Applications/SysMonitor.app` rồi mở luôn. Cần Xcode Command Line
Tools (`xcode-select --install`), không cần thư viện ngoài.

Muốn app tự chạy khi bật máy: mở menu bất kỳ trên thanh menu rồi bật
**Khởi động cùng máy**. Tuỳ chọn này ghi một LaunchAgent vào
`~/Library/LaunchAgents/local.thuyvv.sysmonitor.plist`.

## Xem được những gì

**CPU** — phần trăm đang dùng, tách riêng người dùng / hệ thống / nhàn rỗi,
mức tải từng nhân (nhãn P là nhân hiệu năng, E là nhân tiết kiệm điện),
tải trung bình 1-5-15 phút, số tiến trình và luồng, thời gian máy đã chạy,
5 ứng dụng chiếm CPU nhiều nhất.

**Bộ nhớ** — phần trăm đang dùng, chia theo ứng dụng / hệ thống giữ / đã nén /
bộ đệm tệp / còn trống, áp lực bộ nhớ, mức dùng swap, 5 ứng dụng chiếm RAM
nhiều nhất. Cách tính giống cột "Memory Used" của Activity Monitor, tức là
ứng dụng cộng phần hệ thống giữ cộng phần đã nén.

**Ổ đĩa** — phần trăm đã dùng của ổ khởi động, dung lượng đã dùng / còn trống /
tổng, tốc độ đọc ghi hiện thời, tổng số byte đọc ghi từ lúc khởi động, và
danh sách các ổ đĩa khác đang gắn.

Mỗi menu còn có mục mở Activity Monitor, chọn tốc độ cập nhật (1, 2, 3 hoặc 5
giây) và bật tắt khởi động cùng máy.

## Cấu trúc source

| Tệp | Nội dung |
| --- | --- |
| `Sources/Metrics.swift` | Đọc số liệu hệ thống qua Mach, sysctl, IOKit và `ps` |
| `Sources/MenuViews.swift` | Các thành phần giao diện tự vẽ trong menu |
| `Sources/StatusItems.swift` | Ba mục trên thanh menu và nội dung từng bảng |
| `Sources/AppDelegate.swift` | Vòng lấy mẫu theo nhịp và khởi tạo app |
| `Sources/Formatters.swift` | Định dạng số liệu hiển thị |

Số liệu lấy trực tiếp từ nhân hệ điều hành, không gọi lệnh ngoài trừ `ps` dùng
cho danh sách tiến trình. Toàn bộ vòng lấy mẫu tốn khoảng 0,06 ms mỗi giây.

## Ghi chú kỹ thuật

Khi một menu đang mở, macOS không chạy các khối `DispatchQueue.main.async`,
nhưng `Timer` đăng ký ở chế độ `.common` thì vẫn chạy. Vì vậy luồng nền chỉ ghi
kết quả `ps` vào một vùng nhớ có khoá, còn giao diện đọc lại theo nhịp Timer.
Đổi chỗ này sang callback sẽ làm danh sách tiến trình đứng yên khi menu mở.

Thứ tự ba mục trên thanh menu là CPU, bộ nhớ, ổ đĩa. Do `NSStatusBar` chèn mục
mới vào bên trái nên trong `AppDelegate` chúng được tạo theo thứ tự ngược lại.
Có thể giữ phím Command rồi kéo để đổi chỗ, macOS sẽ nhớ vị trí.

Kiểm tra giao diện nhanh mà không cần bấm chuột:

```bash
~/Applications/SysMonitor.app/Contents/MacOS/SysMonitor --open cpu
```

Thay `cpu` bằng `memory` hoặc `disk` để mở bảng tương ứng. Thêm
`--appearance light` hoặc `--appearance dark` để xem app ở chế độ sáng tối mà
không phải đổi cài đặt của máy.
