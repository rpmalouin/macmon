import XCTest

@testable import MacmonCore

final class StatusLabelTests: XCTestCase {
  func testTextShowsRoundedCpuAndMemory() {
    let label = StatusLabel(cpuPercent: 12.4, memoryPercent: 47.2)
    XCTAssertEqual(label.text, "CPU 12%  MEM 47%")
  }

  func testMemoryAloneDoesNotColourTheDotBelowNinetyFive() {
    XCTAssertEqual(StatusLabel(cpuPercent: 39, memoryPercent: 88).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 0, memoryPercent: 0).load, .clear)
    // A resident local model reads 87-92% "used" as its normal operating point: not a colour at all,
    // or the dot would flip every few seconds as the model's footprint moves.
    XCTAssertEqual(StatusLabel(cpuPercent: 5, memoryPercent: 88).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 5, memoryPercent: 92).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 5, memoryPercent: 95).load, .clear)
  }

  func testModerateFromFortyCpu() {
    XCTAssertEqual(StatusLabel(cpuPercent: 40, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 60, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 75, memoryPercent: 10).load, .moderate)
  }

  func testMemoryAloneNeverMakesItModerate() {
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 89).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 94).load, .clear)
  }

  func testHeavyAboveSeventyFiveCpuOrNinetyFiveMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 76, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 100, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 96).load, .heavy)
  }

  func testTheCompactFormDropsTheMemoryFromTheTextButNotFromTheDot() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 47, swapTotal: 0, swapUsage: 0))

    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 12%  MEM 47%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).load, .clear)

    // Memory leaves the text, not the thresholds: the dot still shows a machine under pressure.
    let busy = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 96, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: busy, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: busy, compact: true).load, .heavy)
  }

  func testLoadFromASampleUsesItsMemoryFraction() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.42,
      memory: .init(ramTotal: 100, ramUsage: 90, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: sample).load, .moderate, "the CPU is over 40%, the memory is not")
    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 42%  MEM 90%")
  }
}
