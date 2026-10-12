import AppKit

// A menu bar app: no Dock icon, no window, just the status item.
@main
struct MacmonApp {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    // `NSApplication.delegate` is a weak reference: this local outlives `run()`, which returns
    // only when the app terminates.
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}
