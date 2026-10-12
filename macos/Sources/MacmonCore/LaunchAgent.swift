import Foundation

/// The LaunchAgent that starts the app at login.
///
/// A plist in `~/Library/LaunchAgents` rather than `SMAppService`: that wants a signing identity,
/// which this Mac has none of. The agent takes effect at the next login — the app is already running
/// when the switch is flipped, which is why installing does not start a second copy.
public enum LaunchAgent {
  public static let label = "com.ronmalouin.macmon"

  /// Where the agent lives.
  public static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/LaunchAgents/\(label).plist")
  }

  /// The agent's contents, running `executable`.
  ///
  /// `KeepAlive` with `SuccessfulExit: false` restarts an app that died badly and leaves a quit
  /// alone: a release build aborts on panic, so a dead sampler should come back, while choosing
  /// Quit in the panel exits zero and stays quit.
  public static func plist(executable: String) -> [String: Any] {
    [
      "Label": label,
      "ProgramArguments": [executable],
      "RunAtLoad": true,
      "KeepAlive": ["SuccessfulExit": false],
      "ProcessType": "Interactive",
    ]
  }

  /// Write the agent for `executable`.
  public static func install(executable: String, at target: URL? = nil) throws {
    let target = target ?? url
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist(executable: executable), format: .xml, options: 0)
    try data.write(to: target, options: .atomic)
  }

  /// Remove the agent, if there is one.
  public static func remove(at target: URL? = nil) throws {
    let target = target ?? url
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
  }

  /// Whether the agent is installed.
  public static func isInstalled(at target: URL? = nil) -> Bool {
    FileManager.default.fileExists(atPath: (target ?? url).path)
  }
}
