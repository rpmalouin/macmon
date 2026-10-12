import XCTest

@testable import MacmonCore

final class StatusLabelTests: XCTestCase {
  func testClearWhileTheKernelStillHasMemoryToHandOut() {
    XCTAssertEqual(StatusLabel(cpuPercent: 39, availablePercent: 15).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 0, availablePercent: 100).load, .clear)
    // This machine's normal operating point: 87-92% "used" with the local model resident, but 15-16%
    // still available. The dot must not colour that, or it would flap as the model's footprint moves.
    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 16).load, .clear)
    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 10).load, .clear)
  }

  func testModerateFromFortyCpuOrUnderTenPercentAvailable() {
    XCTAssertEqual(StatusLabel(cpuPercent: 40, availablePercent: 50).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 60, availablePercent: 50).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 75, availablePercent: 50).load, .moderate)

    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 9.9).load, .moderate)
    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 5).load, .moderate)
  }

  func testHeavyAboveSeventyFiveCpuOrUnderFivePercentAvailable() {
    XCTAssertEqual(StatusLabel(cpuPercent: 76, availablePercent: 50).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 100, availablePercent: 50).load, .heavy)

    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 4.9).load, .heavy)
    XCTAssertEqual(StatusLabel(cpuPercent: 5, availablePercent: 0).load, .heavy)
  }

  func testTheTextKeepsTheUsedFigureWhileTheDotReadsPressure() {
    // The label reports usage because that is what a reader expects to see; the dot reports pressure,
    // and the two legitimately disagree on a machine with a large resident model.
    let sample = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 88, ramAvailable: 15, swapTotal: 0, swapUsage: 0))

    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 12%  MEM 88%")
    XCTAssertEqual(StatusLabel(sample: sample).load, .clear, "15% available is not a colour")
  }

  func testTheCompactFormDropsTheMemoryFromTheTextButNotFromTheDot() {
    let sample = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 47, ramAvailable: 40, swapTotal: 0, swapUsage: 0))

    XCTAssertEqual(StatusLabel(sample: sample).text, "CPU 12%  MEM 47%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: sample, compact: true).load, .clear)

    // Under 5% available: heavy, whatever the text shows.
    let squeezed = Sample.fixture(
      cpuScaledRatio: 0.12, memory: .init(ramTotal: 100, ramUsage: 96, ramAvailable: 2, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: squeezed, compact: true).text, "12%")
    XCTAssertEqual(StatusLabel(sample: squeezed, compact: true).load, .heavy)
  }

  func testLoadFromASampleUsesItsCpuAndItsAvailability() {
    let busyCpu = Sample.fixture(
      cpuScaledRatio: 0.42,
      memory: .init(ramTotal: 100, ramUsage: 30, ramAvailable: 60, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: busyCpu).load, .moderate, "the CPU is over 40%")
    XCTAssertEqual(StatusLabel(sample: busyCpu).text, "CPU 42%  MEM 30%")

    let outOfMemory = Sample.fixture(
      cpuScaledRatio: 0.05,
      memory: .init(ramTotal: 100, ramUsage: 95, ramAvailable: 4, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(StatusLabel(sample: outOfMemory).load, .heavy, "4% available is heavy on an idle CPU")
  }
}
