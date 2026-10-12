import Foundation
import XCTest

@testable import MacmonCore

final class ProcessTests: XCTestCase {
  /// The real thing: the sampler reads this machine's process table.
  func testAProcessSamplerReadsTheMachine() throws {
    let sampler = try ProcessSampler()
    try sampler.warmUp() // the first call reports zero rates

    let busiest = try sampler.next(topN: 8)
    XCTAssertFalse(busiest.isEmpty, "no processes at all?")
    XCTAssertLessThanOrEqual(busiest.count, 8)

    let every = try sampler.next(topN: 0)
    XCTAssertGreaterThan(every.count, 8, "a machine runs more than eight processes")
    for process in every {
      XCTAssertFalse(process.name.isEmpty, "no name for pid \(process.pid)")
      XCTAssertFalse(process.user.isEmpty, "no user for pid \(process.pid)")
    }
  }

  /// This test's own process reads its energy counter, so its row carries watts.
  func testOurOwnProcessCarriesAPowerReading() throws {
    let sampler = try ProcessSampler()
    try sampler.warmUp()

    let own = try XCTUnwrap(
      try sampler.next(topN: 0).first { $0.pid == Int32(ProcessInfo.processInfo.processIdentifier) },
      "this process is not in the list")
    XCTAssertNotNil(own.powerW, "no power for our own process")
  }

  /// The ABI sorts the list, and the app keeps its order.
  func testTheListComesBackBusiestFirst() throws {
    let sampler = try ProcessSampler()
    try sampler.warmUp()

    let cpus = try sampler.next(topN: 8).map(\.cpuPct)
    XCTAssertEqual(cpus, cpus.sorted(by: >), "not busiest first: \(cpus)")
  }
}
