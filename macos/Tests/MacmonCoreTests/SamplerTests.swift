import XCTest

@testable import MacmonCore

final class SamplerTests: XCTestCase {
  /// A document shaped like the ABI's, with one field the app does not read.
  func testDecodesTheFieldsTheAppReadsAndIgnoresTheRest() throws {
    let json = """
      {
        "timestamp": 1791836540.225,
        "cpu_scaled_ratio": 0.125,
        "gpu_power": 0.09,
        "memory": {
          "ram_total": 68719476736,
          "ram_usage": 56580177920,
          "swap_total": 4294967296,
          "swap_usage": 1048576
        },
        "cpu_tiers": [{ "label": "P", "cores": 12 }],
        "fans": [{ "name": "fan0", "rpm": 1200 }]
      }
      """

    let sample = try Sampler.decoder.decode(Sample.self, from: Data(json.utf8))

    XCTAssertEqual(sample.timestamp, 1791836540.225)
    XCTAssertEqual(sample.cpuScaledRatio, 0.125)
    XCTAssertEqual(sample.memory.ramTotal, 68719476736)
    XCTAssertEqual(sample.memory.ramUsage, 56580177920)
    XCTAssertEqual(sample.memory.swapTotal, 4294967296)
    XCTAssertEqual(sample.memory.swapUsage, 1048576)
    XCTAssertEqual(sample.memory.ramFraction, 0.82335, accuracy: 1e-5)
  }

  /// The real thing: the sampler reads this machine, so this test needs real hardware.
  func testASamplerReadsTheMachine() throws {
    let sampler = try Sampler()
    let sample = try sampler.next(durationMs: 100)

    XCTAssertGreaterThan(sample.timestamp, 0)
    XCTAssertGreaterThan(sample.memory.ramTotal, 0)
    XCTAssertLessThanOrEqual(sample.memory.ramUsage, sample.memory.ramTotal)
    XCTAssertTrue((0...1).contains(sample.cpuScaledRatio), "cpu ratio \(sample.cpuScaledRatio)")
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
