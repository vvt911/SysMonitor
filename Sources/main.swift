import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // chỉ nằm trên thanh menu, không có trong Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
