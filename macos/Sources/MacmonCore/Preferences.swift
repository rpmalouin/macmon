import Foundation

/// What the app remembers between launches.
///
/// Kept in `UserDefaults`, not in `~/.config/macmon.json`: that file belongs to the TUI, which drops
/// any field it does not know when it saves, so preferences written there would not survive a TUI run.
public struct Preferences: Equatable {
  /// The intervals the menu offers, in seconds.
  public static let intervals = [1, 2, 5]

  public var intervalSeconds: Int
  /// The status item shows `12%` instead of `CPU 12%  MEM 47%`.
  public var compactLabel: Bool
  public var showsHistory: Bool
  public var showsProcesses: Bool

  public init(
    intervalSeconds: Int = 1, compactLabel: Bool = false, showsHistory: Bool = true,
    showsProcesses: Bool = true
  ) {
    self.intervalSeconds = Self.nearestInterval(intervalSeconds)
    self.compactLabel = compactLabel
    self.showsHistory = showsHistory
    self.showsProcesses = showsProcesses
  }

  /// The polling interval in milliseconds.
  public var intervalMs: UInt32 {
    UInt32(intervalSeconds * 1000)
  }

  /// The offered interval closest to `seconds`: a stored value outside the list, from an older app
  /// or a hand-edited default, still reads as one the app can run.
  public static func nearestInterval(_ seconds: Int) -> Int {
    intervals.min { abs($0 - seconds) < abs($1 - seconds) } ?? intervals[0]
  }
}

/// Reads and writes [`Preferences`].
public final class PreferencesStore {
  private enum Key {
    static let interval = "macmon.intervalSeconds"
    static let compact = "macmon.compactLabel"
    static let history = "macmon.showsHistory"
    static let processes = "macmon.showsProcesses"
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The stored preferences, with the defaults for anything never written.
  public var current: Preferences {
    Preferences(
      intervalSeconds: defaults.object(forKey: Key.interval) as? Int ?? 1,
      compactLabel: defaults.bool(forKey: Key.compact),
      showsHistory: defaults.object(forKey: Key.history) as? Bool ?? true,
      showsProcesses: defaults.object(forKey: Key.processes) as? Bool ?? true)
  }

  public func save(_ preferences: Preferences) {
    defaults.set(preferences.intervalSeconds, forKey: Key.interval)
    defaults.set(preferences.compactLabel, forKey: Key.compact)
    defaults.set(preferences.showsHistory, forKey: Key.history)
    defaults.set(preferences.showsProcesses, forKey: Key.processes)
  }
}
