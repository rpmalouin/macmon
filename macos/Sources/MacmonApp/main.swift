import AppKit

// A menu bar app: no Dock icon, no window, just the status item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
