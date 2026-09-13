import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // chi nam tren thanh menu, khong co trong Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
