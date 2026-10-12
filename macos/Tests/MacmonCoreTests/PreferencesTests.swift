import XCTest

@testable import MacmonCore

final class PreferencesTests: XCTestCase {
  private let suite = "com.ronmalouin.macmon.preferences-tests"

  /// A store on its own defaults suite, cleaned out before and after.
  private func store() -> PreferencesStore {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    addTeardownBlock { defaults.removePersistentDomain(forName: self.suite) }
    return PreferencesStore(defaults: defaults)
  }

  func testTheDefaults() {
    let store = store()
    XCTAssertEqual(store.current, Preferences())
    XCTAssertEqual(store.current.intervalSeconds, 1)
    XCTAssertFalse(store.current.compactLabel)
    XCTAssertTrue(store.current.showsHistory)
    XCTAssertTrue(store.current.showsProcesses)
  }

  func testSettingsSurviveASave() {
    let store = store()
    let written = Preferences(intervalSeconds: 5, compactLabel: true, showsHistory: false, showsProcesses: false)

    store.save(written)

    XCTAssertEqual(store.current, written)
  }

  func testAnIntervalOutsideTheListReadsAsTheNearest() {
    XCTAssertEqual(Preferences(intervalSeconds: 3).intervalSeconds, 2)
    XCTAssertEqual(Preferences(intervalSeconds: 99).intervalSeconds, 5)
    XCTAssertEqual(Preferences(intervalSeconds: 0).intervalSeconds, 1)
    XCTAssertEqual(Preferences.nearestInterval(-4), 1)
  }

  func testTheIntervalInMilliseconds() {
    XCTAssertEqual(Preferences(intervalSeconds: 1).intervalMs, 1000)
    XCTAssertEqual(Preferences(intervalSeconds: 5).intervalMs, 5000)
  }
}
