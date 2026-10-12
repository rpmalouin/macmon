import XCTest

@testable import MacmonCore

final class SamplerTests: XCTestCase {
  /// A document captured from this machine, per-core arrays and all.
  func testDecodesACapturedDocument() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: "sample", withExtension: "json", subdirectory: "Fixtures"),
      "the capture is missing from the test bundle")
    let sample = try Sampler.decoder.decode(Sample.self, from: try Data(contentsOf: url))

    XCTAssertGreaterThan(sample.timestamp, 0)
    XCTAssertGreaterThan(sample.memory.ramTotal, 0)
    XCTAssertLessThanOrEqual(sample.memory.ramUsage, sample.memory.ramTotal)
    XCTAssertTrue((0...1).contains(sample.cpuScaledRatio), "cpu \(sample.cpuScaledRatio)")
    XCTAssertGreaterThan(sample.memory.ramFraction, 0)
    XCTAssertEqual(sample.cpuTiers.count, 2, "the capture is from a two-tier chip")
    XCTAssertEqual(sample.cpuTiers.flatMap(\.cores).count, 18, "the capture is from an 18-core chip")
  }

  /// The real thing: the sampler reads this machine, so this test needs real hardware.
  func testASamplerReadsTheMachineAndItsMachineInformation() throws {
    let sampler = try Sampler()
    let sample = try sampler.next(durationMs: 100)

    XCTAssertGreaterThan(sample.timestamp, 0)
    XCTAssertGreaterThan(sample.memory.ramTotal, 0)
    XCTAssertTrue((0...1).contains(sample.cpuScaledRatio), "cpu ratio \(sample.cpuScaledRatio)")
    XCTAssertFalse(sample.cpuTiers.isEmpty, "no CPU tiers")

    let soc = try sampler.soc()
    XCTAssertFalse(soc.chipName.isEmpty)
    XCTAssertGreaterThan(soc.memoryGb, 0)
  }

  /// Two intervals in a row share the sampler's baseline, as the C ABI documents.
  func testConsecutiveSamplesBothDecode() throws {
    let sampler = try Sampler()
    let first = try sampler.next(durationMs: 100)
    let second = try sampler.next(durationMs: 100)

    XCTAssertGreaterThanOrEqual(second.timestamp, first.timestamp)
    XCTAssertTrue((0...1).contains(second.cpuScaledRatio), "cpu ratio \(second.cpuScaledRatio)")
  }
}
