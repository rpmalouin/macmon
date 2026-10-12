import CoreGraphics
import Foundation

/// A fixed window of recent samples, oldest first.
///
/// Pure: it holds the last `capacity` samples and splits them where the machine stopped reporting,
/// so the panel can draw them and a test can read them without a screen.
public struct History: Equatable {
  /// One sample of the window, reduced to what the history block draws.
  private struct Point: Equatable {
    let timestamp: Double
    let cpu: Double
    let gpu: Double
  }

  /// How many samples the window holds.
  public let capacity: Int
  /// A break longer than this between two samples is a gap, not a line. It follows the sampling
  /// interval, so it belongs to whoever sets that.
  public var gapAfter: TimeInterval

  private var points: [Point] = []

  public init(capacity: Int = 60, gapAfter: TimeInterval = 2.5) {
    self.capacity = max(2, capacity)
    self.gapAfter = gapAfter
  }

  public var count: Int { points.count }

  /// Add a sample.
  ///
  /// A sample at or before the newest one in the window is ignored: publishing the same sample
  /// twice cannot fold the window, and nothing older can arrive out of order without being dropped.
  public mutating func append(_ sample: Sample) {
    if let last = points.last, sample.timestamp <= last.timestamp { return }
    points.append(Point(timestamp: sample.timestamp, cpu: sample.cpuScaledRatio, gpu: sample.gpuScaledRatio))
    if points.count > capacity {
      points.removeFirst(points.count - capacity)
    }
  }

  /// The window as series of runs, or nil while there is not enough of it to draw.
  public func sparkline() -> Sparkline? {
    guard points.count >= 2 else { return nil }
    let span = (points.last?.timestamp ?? 0) - (points.first?.timestamp ?? 0)
    return Sparkline(cpu: runs { $0.cpu }, gpu: runs { $0.gpu }, span: span)
  }

  /// One series of the window, split into runs of consecutive samples.
  private func runs(_ value: (Point) -> Double) -> [Sparkline.Run] {
    var runs: [Sparkline.Run] = []
    var current: [Double] = []
    var previous: Double?

    for point in points {
      if let previous, point.timestamp - previous > gapAfter {
        runs.append(Sparkline.Run(values: current))
        current = []
      }
      current.append(value(point))
      previous = point.timestamp
    }
    if !current.isEmpty {
      runs.append(Sparkline.Run(values: current))
    }
    return runs.filter { !$0.values.isEmpty }
  }
}

/// What the panel's history block draws: the two series, each in runs, with the range they share.
public struct Sparkline: Equatable {
  /// One unbroken run of values.
  public struct Run: Equatable {
    public let values: [Double]
  }

  public let cpu: [Run]
  public let gpu: [Run]
  /// How long the window covers, in seconds.
  public let span: TimeInterval
  /// The value the top of the block stands for: the window's maximum, never below `floor`, so a
  /// quiet machine still shows the shape of its own noise instead of a flat line at the bottom.
  public let scale: Double

  public init(cpu: [Run], gpu: [Run], span: TimeInterval, floor: Double = 0.05) {
    self.cpu = cpu
    self.gpu = gpu
    self.span = span
    scale = max(floor, (cpu + gpu).flatMap(\.values).max() ?? 0)
  }

  /// Whether the window has any GPU at all: a machine without GPU counters draws no second line.
  public var hasGPU: Bool {
    gpu.contains { $0.values.contains { $0 > 0 } }
  }

  /// The points of one run in a block of `size`: x across the block, y from its top down.
  ///
  /// A run of fewer than two values has no line to draw and returns nothing.
  public static func points(values: [Double], size: CGSize, scale: Double) -> [CGPoint] {
    guard values.count >= 2, size.width > 0, size.height > 0, scale > 0 else { return [] }

    let step = size.width / CGFloat(values.count - 1)
    return values.enumerated().map { index, value in
      let height = CGFloat(min(max(value, 0), scale) / scale)
      return CGPoint(x: CGFloat(index) * step, y: size.height * (1 - height))
    }
  }
}
