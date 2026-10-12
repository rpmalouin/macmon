import XCTest

@testable import MacmonCore

final class StatusLabelTests: XCTestCase {
  func testTextShowsRoundedCpuAndMemory() {
    let label = StatusLabel(cpuPercent: 12.4, memoryPercent: 47.2)
    XCTAssertEqual(label.text, "CPU 12%  MEM 47%")
  }

  func testClearBelowFortyCpuAndEightyEightMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 39, memoryPercent: 88).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 0, memoryPercent: 0).load, .clear)
    // A resident local model reads 88-90% "used"; that is not a red dot.
    XCTAssertEqual(StatusLabel(cpuPercent: 5, memoryPercent: 88).load, .clear)
  }

  func testModerateFromFortyCpu() {
    XCTAssertEqual(StatusLabel(cpuPercent: 40, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 60, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 75, memoryPercent: 10).load, .moderate)
  }

  func testModerateAboveEightyEightMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 89).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 93).load, .moderate)
  }

  func testHeavyAboveSeventyFiveCpuOrNinetyThreeMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 76, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 100, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 94).load, .heavy)
  }

  func testTheCompactFormDropsTheMemoryFromTheTextButNotFromTheDot() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 47, swapTotal: 0, swapUsage: 0))

    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 12%  MEM 47%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).load, .clear)

    // Memory leaves the text, not the thresholds: the dot still shows a machine under pressure.
    let busy = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 95, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: busy, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: busy, compact: true).load, .heavy)
  }

  func testLoadFromASampleUsesItsMemoryFraction() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.42,
      memory: .init(ramTotal: 100, ramUsage: 90, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: sample).load, .moderate, "90% used is not yet a red dot")
    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 42%  MEM 90%")
  }
}
