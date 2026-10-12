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
    load = Self.load(cpuPercent: cpu, availablePercent: sample.memory.availableFraction * 100)
  }

  /// Plain percentages, for tests and for a caller that already has them.
  public init(cpuPercent: Double, availablePercent: Double) {
    text = "CPU \(Int(cpuPercent.rounded()))%  MEM —"
    load = Self.load(cpuPercent: cpuPercent, availablePercent: availablePercent)
  }

  /// Heavy above 75% CPU, or under 5% of memory still available; moderate above 40% CPU, or under
  /// 10% available; clear otherwise.
  ///
  /// Memory is judged by what the kernel can still hand out rather than by how much is in use.
  /// `ram_usage` is Activity Monitor's "Memory Used", which counts reclaimable `inactive` pages: on a
  /// machine keeping a ~35 GB local model resident it sits at 87–92% as the normal operating point,
  /// so any threshold on it either fires constantly or flaps. Available memory does not: it reads
  /// 15–16% on this machine with the model loaded, clear of the 10% line by design.
  static func load(cpuPercent: Double, availablePercent: Double) -> Load {
    if cpuPercent > 75 || availablePercent < 5 { return .heavy }
    if cpuPercent >= 40 || availablePercent < 10 { return .moderate }
    return .clear
  }
}
