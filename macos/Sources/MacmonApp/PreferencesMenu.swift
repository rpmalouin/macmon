import AppKit
import MacmonCore

/// The right-click menu: how often to sample, what the panel shows, and starting at login.
///
/// A menu rather than a preferences block inside the panel: it is the idiom for a status item, and it
/// costs a 300 pt panel no room. The item states are built on every right-click, so they always
/// describe what is in force rather than what was in force when the app started.
@MainActor
final class PreferencesMenu: NSObject {
  private let current: () -> Preferences
  private let apply: (Preferences) -> Void

  init(current: @escaping () -> Preferences, apply: @escaping (Preferences) -> Void) {
    self.current = current
    self.apply = apply
  }

  func build() -> NSMenu {
    let preferences = current()
    let menu = NSMenu()

    let interval = NSMenuItem(title: "Update every", action: nil, keyEquivalent: "")
    interval.submenu = intervalMenu(selected: preferences.intervalSeconds)
    menu.addItem(interval)

    menu.addItem(toggle("Compact label", on: preferences.compactLabel, action: #selector(toggleCompactLabel)))
    menu.addItem(toggle("Show history", on: preferences.showsHistory, action: #selector(toggleHistory)))
    menu.addItem(toggle("Show processes", on: preferences.showsProcesses, action: #selector(toggleProcesses)))
    menu.addItem(.separator())
    menu.addItem(toggle("Start at login", on: LaunchAgent.isInstalled(), action: #selector(toggleLogin)))
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit macmon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }

  private func intervalMenu(selected: Int) -> NSMenu {
    let menu = NSMenu()
    for seconds in Preferences.intervals {
      let item = NSMenuItem(title: "\(seconds) s", action: #selector(setInterval(_:)), keyEquivalent: "")
      item.target = self
      item.tag = seconds
      item.state = seconds == selected ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func toggle(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = on ? .on : .off
    return item
  }

  @objc private func setInterval(_ item: NSMenuItem) {
    var preferences = current()
    preferences.intervalSeconds = Preferences.nearestInterval(item.tag)
    apply(preferences)
  }

  @objc private func toggleCompactLabel() {
    var preferences = current()
    preferences.compactLabel.toggle()
    apply(preferences)
  }

  @objc private func toggleHistory() {
    var preferences = current()
    preferences.showsHistory.toggle()
    apply(preferences)
  }

  @objc private func toggleProcesses() {
    var preferences = current()
    preferences.showsProcesses.toggle()
    apply(preferences)
  }

  @objc private func toggleLogin() {
    if LaunchAgent.isInstalled() {
      try? LaunchAgent.remove()
    } else if let executable = Bundle.main.executablePath {
      try? LaunchAgent.install(executable: executable)
    }
  }
}
