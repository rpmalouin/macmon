import CoreGraphics
import XCTest

@testable import MacmonCore

final class HistoryTests: XCTestCase {
  // MARK: - The window

  func testTheWindowDropsItsOldestSample() {
    var history = History(capacity: 60)
    for index in 0..<61 {
      history.append(sample(at: Double(index), cpu: Double(index) / 100))
    }

    XCTAssertEqual(history.count, 60, "the window holds 60, not 61")
    let cpu = try? XCTUnwrap(history.sparkline()?.cpu)
    XCTAssertEqual(cpu?.first?.values.first, 0.01, "the first sample fell out of the window")
    XCTAssertEqual(cpu?.first?.values.last, 0.60)
  }

  func testTheSameSampleIsKeptOnce() {
    var history = History()
    let one = sample(at: 10, cpu: 0.2)

    history.append(one)
    history.append(one)
    XCTAssertEqual(history.count, 1, "publishing the same sample twice folds the window")

    history.append(sample(at: 20, cpu: 0.3))
    history.append(one)
    XCTAssertEqual(history.count, 2, "an older sample is ignored, not inserted")
  }

  func testTwoSamplesAreTheLeastItDraws() {
    var history = History()
    XCTAssertNil(history.sparkline(), "an empty window has nothing to draw")

    history.append(sample(at: 0, cpu: 0.1))
    XCTAssertNil(history.sparkline(), "one sample is a dot, not a line")

    history.append(sample(at: 1, cpu: 0.2))
    XCTAssertNotNil(history.sparkline())
  }

  // MARK: - Gaps

  func testAGapSplitsTheLineInTwo() {
    var history = History(gapAfter: 2.5)
    for second in [0.0, 1.0, 2.0, 10.0, 11.0] {
      history.append(sample(at: second, cpu: second / 100))
    }

    let sparkline = try? XCTUnwrap(history.sparkline())
    XCTAssertEqual(sparkline?.cpu.count, 2, "a break of eight seconds is not a line")
    XCTAssertEqual(sparkline?.cpu[0].values.count, 3)
    XCTAssertEqual(sparkline?.cpu[1].values.count, 2)
    XCTAssertEqual(sparkline?.span, 11)
  }

  func testASteadyWindowStaysOneRun() {
    var history = History(gapAfter: 2.5)
    for second in 0..<5 {
      history.append(sample(at: Double(second), cpu: 0.1))
    }

    XCTAssertEqual(history.sparkline()?.cpu.count, 1)
  }

  // MARK: - What the block draws

  func testTheScaleFollowsTheWindowWithAFloor() {
    var quiet = History()
    quiet.append(sample(at: 0, cpu: 0.01))
    quiet.append(sample(at: 1, cpu: 0.02))
    XCTAssertEqual(quiet.sparkline()?.scale, 0.05, "a quiet machine keeps the floor")

    var busy = History()
    busy.append(sample(at: 0, cpu: 0.1))
    busy.append(sample(at: 1, cpu: 0.42))
    XCTAssertEqual(busy.sparkline()?.scale, 0.42, "the top of the block is the window's maximum")
  }

  func testAGPUAtZeroDrawsNoSecondLine() {
    var cpuOnly = History()
    cpuOnly.append(sample(at: 0, cpu: 0.1, gpu: 0))
    cpuOnly.append(sample(at: 1, cpu: 0.2, gpu: 0))
    XCTAssertEqual(cpuOnly.sparkline()?.hasGPU, false)

    var withGPU = History()
    withGPU.append(sample(at: 0, cpu: 0.1, gpu: 0.04))
    withGPU.append(sample(at: 1, cpu: 0.2, gpu: 0.06))
    XCTAssertEqual(withGPU.sparkline()?.hasGPU, true)
  }

  func testARunOfOneValueHasNoPoints() {
    XCTAssertEqual(Sparkline.points(values: [], size: CGSize(width: 100, height: 20), scale: 1), [])
    XCTAssertEqual(Sparkline.points(values: [0.5], size: CGSize(width: 100, height: 20), scale: 1), [])
  }

  func testPointsSpanTheBlockWithTheTopAtTheHighestValue() {
    let points = Sparkline.points(
      values: [0, 0.5, 1], size: CGSize(width: 100, height: 20), scale: 1)

    XCTAssertEqual(points.count, 3)
    XCTAssertEqual(points[0], CGPoint(x: 0, y: 20), "zero sits on the bottom edge")
    XCTAssertEqual(points[1], CGPoint(x: 50, y: 10), "half scale sits in the middle")
    XCTAssertEqual(points[2], CGPoint(x: 100, y: 0), "the maximum sits on the top edge")
  }

  func testPointsAboveTheScaleAreClampedToTheBlock() {
    let points = Sparkline.points(
      values: [0, 2], size: CGSize(width: 10, height: 20), scale: 1)
    XCTAssertEqual(points[1].y, 0, "a value above the scale still draws inside the block")
  }

  private func sample(at timestamp: Double, cpu: Double, gpu: Double = 0) -> Sample {
    Sample.fixture(timestamp: timestamp, cpuScaledRatio: cpu, gpuScaledRatio: gpu)
  }
}
