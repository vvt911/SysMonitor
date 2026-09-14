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

Script dựng `~/Applications/SysMonitor.app` rồi mở luôn. Cần macOS 14 trở lên và Xcode
Command Line Tools (`xcode-select --install`), không cần thư viện ngoài.

Muốn app tự chạy khi bật máy: mở Cài đặt rồi bật **Khởi động cùng máy**. Tuỳ chọn này ghi một LaunchAgent vào
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

Mỗi menu còn có mục mở Activity Monitor và mục **Cài đặt…** với phím tắt ⌘,. Mở lại
SysMonitor.app khi app đang chạy cũng hiện cửa sổ Cài đặt.

Đang mở một bảng mà bấm sang mục khác thì chuyển thẳng sang bảng đó, không phải
bấm hai lần.

Thanh menu thiếu chỗ thì app bớt chỉ số theo thứ tự ưu tiên: ổ đĩa trước, rồi đến CPU,
RAM giữ tới cùng. Các chỉ số còn lại dồn sang phải, vẫn theo thứ tự CPU, RAM, ổ đĩa,
nằm sát biểu tượng bên cạnh. Việc tự nhường chỗ chỉ tính theo màn hình có tai thỏ, và
áp dụng cho mọi màn hình vì macOS không cho một mục thanh menu hiện riêng từng màn hình.

## Cài đặt

| Nhóm | Tuỳ chọn |
| --- | --- |
| Chung | Ngôn ngữ theo hệ thống, tiếng Việt hoặc tiếng Anh. Khởi động cùng máy. Tốc độ cập nhật. |
| Chỉ số trên thanh menu | Bật tắt từng chỉ số, luôn giữ ít nhất một. Đổi thứ tự từ trái sang phải. |
| Cách hiển thị | Hiện biểu tượng. Số chữ số thập phân. Tô màu con số khi vượt ngưỡng cảnh báo. Chọn ổ đĩa hiện trên thanh menu. |
| Khi thanh menu đầy | Bật tắt việc tự bớt chỉ số. Thứ tự ưu tiên giữ lại. |
| Bảng chi tiết | Số tiến trình liệt kê. Ngưỡng cảnh báo và ngưỡng nguy hiểm dùng để tô màu. |

Mọi thay đổi áp dụng ngay, kể cả ngôn ngữ. Ngôn ngữ mặc định là tiếng Việt. Cài đặt lưu trong
`defaults read local.thuyvv.sysmonitor`.

Chỉ số tắt trong Cài đặt thì ô của nó bị ẩn hẳn bằng `isVisible` nên không để lại khe
trống. Các ô bị ẩn luôn là ô bên trái vì chỉ số dồn sang phải, nên bật lại thì ô xuất
hiện ở mép trái vẫn đúng chỗ.

## Cấu trúc source

| Tệp | Nội dung |
| --- | --- |
| `Sources/Metrics.swift` | Đọc số liệu hệ thống qua Mach, sysctl, IOKit và `ps` |
| `Sources/MenuViews.swift` | Các thành phần giao diện tự vẽ trong menu |
| `Sources/StatusItems.swift` | Ba ô trên thanh menu và nội dung từng bảng |
| `Sources/AppSettings.swift` | Cài đặt lưu lại, ngôn ngữ, khởi động cùng máy |
| `Sources/SettingsWindow.swift` | Cửa sổ Cài đặt viết bằng SwiftUI |
| `Sources/AppDelegate.swift` | Vòng lấy mẫu, chuyển menu và nhường chỗ khi thanh menu đầy |
| `Sources/MenuBarSpace.swift` | Đọc chỗ trống thanh menu của từng màn hình |
| `Sources/Formatters.swift` | Định dạng số liệu hiển thị |

Số liệu lấy trực tiếp từ nhân hệ điều hành, không gọi lệnh ngoài trừ `ps` dùng
cho danh sách tiến trình. Toàn bộ vòng lấy mẫu tốn khoảng 0,06 ms mỗi giây.

## Ghi chú kỹ thuật

Khi một menu đang mở, macOS không chạy các khối `DispatchQueue.main.async`,
nhưng `Timer` đăng ký ở chế độ `.common` thì vẫn chạy. Vì vậy luồng nền chỉ ghi
kết quả `ps` vào một vùng nhớ có khoá, còn giao diện đọc lại theo nhịp Timer.
Đổi chỗ này sang callback sẽ làm danh sách tiến trình đứng yên khi menu mở.

Khi một menu đang mở, cú bấm sang mục khác bị vòng theo dõi của menu nuốt mất
nên mục kia không hề nhận được, mặc định phải bấm hai lần. App bắt lúc menu vừa
đóng, thấy con trỏ đang nằm trên mục nào thì mở menu của mục đó. Vị trí đọc từ
khung cửa sổ thật lúc đó chứ không phải toạ độ cố định.

macOS mất khoảng 270 ms mới đóng xong menu cũ sau cú bấm, giữ chuột lâu hay nhả
ngay đều vậy, và tự gọi `cancelTrackingWithoutAnimation` cũng không nhanh hơn.
Đó là trần của cách làm bằng NSMenu, muốn nhanh hơn thì phải thay menu bằng cửa
sổ tự vẽ.

Thanh menu có ba ô cố định, tạo một lần lúc mở app theo thứ tự từ phải sang trái vì
`NSStatusBar` chèn mục mới vào bên trái. Các ô không bao giờ bị gỡ, chỉ đổi nội dung.

Khi thanh menu thiếu chỗ, Control Center tự chọn mục phải ẩn và chọn không nhất quán:
thiếu chỗ cho một mục thì nó ẩn RAM, thiếu chỗ cho hai mục thì nó lại giữ RAM mà ẩn
hai mục kia. Vì vậy app tự nhường chỗ. App đọc danh sách cửa sổ thanh menu của Control
Center, trong đó mục bị ẩn vẫn có mặt nhưng bị đánh dấu không hiện, nên không cần quyền
ghi màn hình. Phần bên phải tai thỏ có bề rộng cố định, nên app tính thẳng ra hiện được
bao nhiêu chỉ số rồi đổi một lần.

Bớt chỉ số thì ô bên trái nhất bị thu độ rộng về 0 và các chỉ số dồn sang phải. Các
cách khác đều đã thử và hỏng. Gỡ rồi tạo lại mục thì Control Center giữ mục mới ẩn gần
nửa giây nên thanh menu nháy. Bật lại bằng `isVisible` thì mục bị chèn sang mép trái
làm lệch thứ tự. Gỡ hoặc ẩn một mục đang bị Control Center ẩn thì để lại cửa sổ ma hàng
chục giây. Ô thu gọn vẫn chiếm lề 16 pt của Control Center, thử bốn cách đều không bỏ
được, nên nó được đặt ở mép trái để khe trống lẫn vào khoảng trống sẵn có thay vì chen
giữa các biểu tượng.

App đọc dày khi có dấu hiệu thanh menu vừa đổi: ô của app bị dời, đổi cỡ hoặc bị ẩn,
một app mở hoặc thoát, màn hình thay đổi. Bình thường mỗi giây đọc một lần. Thiếu chỗ
thì bớt ngay. Có chỗ thì đợi hai lần đọc liền nhau cùng kết quả mới thêm, và chừa thêm
10 pt để con số đổi độ dài không làm chỉ số nhảy qua lại. Mục của app khác bị ẩn dù thừa
chỗ quá 1 giây là cửa sổ ma sót lại khi app đó thoát, và bị bỏ qua. Ô của chính app thì
luôn được tính, vì Control Center có lúc giữ ẩn một mục dù về số học là vừa chỗ.

Kiểm tra giao diện nhanh mà không cần bấm chuột:

```bash
~/Applications/SysMonitor.app/Contents/MacOS/SysMonitor --open cpu
```

Thay `cpu` bằng `memory` hoặc `disk` để mở bảng tương ứng, hoặc dùng `--settings` để
mở thẳng cửa sổ Cài đặt. Thêm
`--appearance light` hoặc `--appearance dark` để xem app ở chế độ sáng tối mà
không phải đổi cài đặt của máy.
