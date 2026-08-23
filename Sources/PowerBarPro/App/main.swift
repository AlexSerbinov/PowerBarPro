import Cocoa

let app = NSApplication.shared
// Set accessory BEFORE run() to prevent any dock icon flash
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
