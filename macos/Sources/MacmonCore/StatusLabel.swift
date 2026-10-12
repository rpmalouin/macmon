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

  /// Heavy above 75% CPU, or above 95% memory; moderate from 40% CPU; clear below.
  ///
  /// CPU carries the bands and memory is a single high-water line, because the memory number is
  /// Activity Monitor's "Memory Used" and it counts `inactive` pages, which are reclaimable. On this
  /// machine, which keeps a ~35 GB local model resident, that reads 87–92% as its normal operating
  /// point with the swap file untouched — so any threshold inside that band makes the dot flip
  /// between colours every few seconds. Above 95% something has joined the model, and that is worth a
  /// red dot; everything else is the panel's Memory row.
  static func load(cpuPercent: Double, memoryPercent: Double) -> Load {
    if cpuPercent > 75 || memoryPercent > 95 { return .heavy }
    if cpuPercent >= 40 { return .moderate }
    return .clear
  }
}
