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

  /// Read one sample, as `CPU 12%  MEM 47%`.
  public init(sample: Sample) {
    let cpu = (sample.cpuScaledRatio * 100).rounded()
    let memory = (sample.memory.ramFraction * 100).rounded()
    text = "CPU \(Int(cpu))%  MEM \(Int(memory))%"
    load = Self.load(cpuPercent: cpu, memoryPercent: memory)
  }

  /// Plain percentages, for tests and for a caller that already has them.
  public init(cpuPercent: Double, memoryPercent: Double) {
    text = "CPU \(Int(cpuPercent.rounded()))%  MEM \(Int(memoryPercent.rounded()))%"
    load = Self.load(cpuPercent: cpuPercent, memoryPercent: memoryPercent)
  }

  /// Heavy above 75% CPU or 85% memory; moderate from 40% CPU or above 70% memory; clear below.
  static func load(cpuPercent: Double, memoryPercent: Double) -> Load {
    if cpuPercent > 75 || memoryPercent > 85 { return .heavy }
    if cpuPercent >= 40 || memoryPercent > 70 { return .moderate }
    return .clear
  }
}
