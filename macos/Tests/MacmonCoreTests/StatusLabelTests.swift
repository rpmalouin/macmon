import XCTest

@testable import MacmonCore

final class StatusLabelTests: XCTestCase {
  func testTextShowsRoundedCpuAndMemory() {
    let label = StatusLabel(cpuPercent: 12.4, memoryPercent: 47.2)
    XCTAssertEqual(label.text, "CPU 12%  MEM 47%")
  }

  func testClearBelowFortyCpuAndSeventyMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 39, memoryPercent: 70).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 0, memoryPercent: 0).load, .clear)
  }

  func testModerateFromFortyCpu() {
    XCTAssertEqual(StatusLabel(cpuPercent: 40, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 60, memoryPercent: 10).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 75, memoryPercent: 10).load, .moderate)
  }

  func testModerateAboveSeventyMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 71).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 85).load, .moderate)
  }

  func testHeavyAboveSeventyFiveCpuOrEightyFiveMemory() {
    XCTAssertEqual(StatusLabel(cpuPercent: 76, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 100, memoryPercent: 10).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 10, memoryPercent: 86).load, .heavy)
  }

  func testLoadFromASampleUsesItsMemoryFraction() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.42,
      memory: .init(ramTotal: 100, ramUsage: 90, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: sample).load, .heavy)
    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 42%  MEM 90%")
  }
}
