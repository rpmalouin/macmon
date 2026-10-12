import XCTest

@testable import MacmonCore

final class LaunchAgentTests: XCTestCase {
  func testTheAgentRunsTheAppAtLoginAndReturnsAfterABadExit() throws {
    let plist = LaunchAgent.plist(executable: "/Applications/Macmon.app/Contents/MacOS/Macmon")

    XCTAssertEqual(plist["Label"] as? String, LaunchAgent.label)
    XCTAssertEqual(plist["RunAtLoad"] as? Bool, true, "the app starts at login")
    XCTAssertEqual(
      plist["ProgramArguments"] as? [String], ["/Applications/Macmon.app/Contents/MacOS/Macmon"])

    let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Bool])
    XCTAssertEqual(
      keepAlive["SuccessfulExit"], false, "a bad exit is restarted, an explicit quit is left alone")
  }

  func testInstallWritesAPlistAndRemoveTakesItAway() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "macmon-agent-\(UUID().uuidString).plist")
    addTeardownBlock { try? LaunchAgent.remove(at: url) }

    XCTAssertFalse(LaunchAgent.isInstalled(at: url))

    try LaunchAgent.install(executable: "/tmp/Macmon", at: url)
    XCTAssertTrue(LaunchAgent.isInstalled(at: url))

    // What was written is a plist the system would read back.
    let data = try Data(contentsOf: url)
    let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    XCTAssertEqual(parsed?["Label"] as? String, LaunchAgent.label)

    try LaunchAgent.remove(at: url)
    XCTAssertFalse(LaunchAgent.isInstalled(at: url))
  }
}
