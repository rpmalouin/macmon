import Foundation

/// What the status item shows for one sample.
///
/// Pure, so the thresholds are testable without a screen.
public struct StatusLabel: Equatable {
  /// How loaded the machine reads, and the colour of the dot beside the text.
  public enum Load: String, Equatable {
    case clear
    case moderate
    case heavy
  }

  public let text: String
  public let load: Load

  /// Read one sample, as `CPU 12%  MEM 47%`, or as `12%` when the label is compact.
  public init(sample: Sample, compact: Bool = false) {
    let cpu = (sample.cpuScaledRatio * 100).rounded()
    let memory = (sample.memory.ramFraction * 100).rounded()
    text = compact ? "\(Int(cpu))%" : "CPU \(Int(cpu))%  MEM \(Int(memory))%"
    load = Self.load(cpuPercent: cpu, memoryPercent: memory)
  }

  /// Plain percentages, for tests and for a caller that already has them.
  public init(cpuPercent: Double, memoryPercent: Double) {
    text = "CPU \(Int(cpuPercent.rounded()))%  MEM \(Int(memoryPercent.rounded()))%"
    load = Self.load(cpuPercent: cpuPercent, memoryPercent: memoryPercent)
  }

  /// Heavy above 75% CPU or 93% memory; moderate from 40% CPU or above 88% memory; clear below.
  ///
  /// The memory thresholds sit near the top on purpose. The number is Activity Monitor's "Memory
  /// Used" (active + inactive + wired + compressed), and `inactive` is reclaimable: on this machine,
  /// which keeps a ~35 GB local model resident, it reads 88–90% while macOS still has 10 GB or more
  /// to give and the swap file sits untouched. Above 93% something else is eating memory on top of
  /// the model, and that is worth a red dot.
  static func load(cpuPercent: Double, memoryPercent: Double) -> Load {
    if cpuPercent > 75 || memoryPercent > 93 { return .heavy }
    if cpuPercent >= 40 || memoryPercent > 88 { return .moderate }
    return .clear
  }
}
