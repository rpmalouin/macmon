import AppKit
import MacmonCore

/// The menu bar item: the status label, its dot, and a menu.
///
/// The item is an `NSStatusItem` rather than a SwiftUI `MenuBarExtra` because the threshold dot
/// carries colour: an attributed title is ours to set and to test, while a menu bar extra's label
/// rendering is not. The panel (step 3 of the plan) is SwiftUI, hosted in a popover from here.
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let monitor = Monitor()
  private var item: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.menu = buildMenu()
    self.item = item
    if ProcessInfo.processInfo.environment["MACMON_APP_DEBUG"] != nil {
      print("status item: button=\(item.button != nil) visible=\(item.isVisible)")
      fflush(stdout)
    }

    monitor.onUpdate = { [weak self] in self?.refresh() }
    monitor.start()
    refresh()
  }

  func applicationWillTerminate(_ notification: Notification) {
    monitor.stop()
  }

  /// Draw the last sample, or say that there is none yet.
  private func refresh() {
    let label = monitor.sample.map(StatusLabel.init(sample:))
    item?.button?.attributedTitle = Self.attributedTitle(label)

    // MACMON_APP_DEBUG=1 prints what the item shows, for a run without eyes on the menu bar.
    if ProcessInfo.processInfo.environment["MACMON_APP_DEBUG"] != nil {
      let state = label.map { "\($0.text)  [\($0.load.rawValue)]" } ?? "no sample yet"
      let stamp = monitor.sample.map { String(format: "%.3f", $0.timestamp) } ?? "-"
      print("\(stamp)  \(state)\(monitor.failure.map { "  (\($0))" } ?? "")")
      fflush(stdout) // a redirected stdout is block-buffered, and a kill would lose it
    }
  }

  private static func attributedTitle(_ label: StatusLabel?) -> NSAttributedString {
    let text = label?.text ?? "macmon —"
    let title = NSMutableAttributedString(
      string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)])
    title.append(NSAttributedString(string: " ●", attributes: [.foregroundColor: color(label?.load)]))
    return title
  }

  private static func color(_ load: StatusLabel.Load?) -> NSColor {
    switch load {
    case .clear: .systemGreen
    case .moderate: .systemYellow
    case .heavy: .systemRed
    case nil: .secondaryLabelColor
    }
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "macmon", action: nil, keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit macmon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }
}
