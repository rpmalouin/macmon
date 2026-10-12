import AppKit
import MacmonCore
import SwiftUI

/// The menu bar item: the status label, its dot, and the panel behind it.
///
/// The item is an `NSStatusItem` rather than a SwiftUI `MenuBarExtra` because the threshold dot
/// carries colour: an attributed title is ours to set and to test, while a menu bar extra's label
/// rendering is not. The panel itself is SwiftUI, hosted in a popover from here.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let monitor = Monitor()
  private let panel = PanelModel()
  private let popover = NSPopover()
  private var item: NSStatusItem?

  private var debug: Bool { ProcessInfo.processInfo.environment["MACMON_APP_DEBUG"] != nil }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    self.item = item

    let controller = NSHostingController(rootView: DashboardView(model: panel))
    controller.sizingOptions = [.preferredContentSize]
    popover.contentViewController = controller
    popover.behavior = .transient

    if debug {
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

  @objc private func togglePopover() {
    guard let button = item?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  /// Draw the last sample: the status label, and the panel's rows.
  private func refresh() {
    let label = monitor.sample.map(StatusLabel.init(sample:))
    item?.button?.attributedTitle = Self.attributedTitle(label)

    if let sample = monitor.sample {
      panel.dashboard = Dashboard(sample: sample, soc: monitor.soc)
    }
    panel.failure = monitor.failure

    // MACMON_APP_DEBUG=1 prints what the item shows, for a run without eyes on the menu bar.
    if debug {
      let state = label.map { "\($0.text)  [\($0.load.rawValue)]" } ?? "no sample yet"
      let stamp = monitor.sample.map { String(format: "%.3f", $0.timestamp) } ?? "-"
      print("\(stamp)  \(state)\(monitor.failure.map { "  (\($0))" } ?? "")")
      fflush(stdout) // a redirected stdout is block-buffered, and a kill would lose it
    }

    // MACMON_APP_DEBUG_POPOVER=1 opens the panel, exercising the path a click takes.
    if ProcessInfo.processInfo.environment["MACMON_APP_DEBUG_POPOVER"] != nil, !popover.isShown,
      panel.dashboard != nil
    {
      togglePopover()
      if debug {
        print("popover shown: \(popover.isShown)")
        fflush(stdout)
      }
    }

    // MACMON_APP_DEBUG_PNG=<path> writes the panel as it renders, to check it without a screen.
    if let path = ProcessInfo.processInfo.environment["MACMON_APP_DEBUG_PNG"] {
      writePanelImage(to: path)
    }
  }

  /// Render the panel to a PNG, for a headless check of the layout.
  ///
  /// `ImageRenderer` rasterizes the SwiftUI view directly: drawing a hosting view through
  /// `cacheDisplay` without a window loses the text, which is exactly what this is meant to show.
  private func writePanelImage(to path: String) {
    let renderer = ImageRenderer(content: DashboardView(model: panel))
    renderer.scale = 2
    guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:])
    else { return }

    try? data.write(to: URL(fileURLWithPath: path))
    if debug {
      print("panel: wrote \(path) (\(Int(image.size.width))x\(Int(image.size.height)))")
      fflush(stdout)
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
}
