import Foundation

/// One line of the panel, already formatted. `fraction`, where there is one, is 0...1: the rows
/// are built here, so a bar cannot be drawn out of range.
public struct DashboardRow: Equatable, Identifiable {
  public let id: String
  public let label: String
  /// The value, aligned right.
  public let value: String
  /// A secondary value, such as a frequency.
  public let detail: String?
  /// 0...1 when the row draws a bar, nil when it draws only text.
  public let fraction: Double?
  /// Whether the row belongs to the one above it, as a CPU tier belongs to its package.
  public let indented: Bool

  public init(
    id: String, label: String, value: String, detail: String? = nil, fraction: Double? = nil,
    indented: Bool = false
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.detail = detail
    self.fraction = fraction
    self.indented = indented
  }
}

/// One titled group of rows.
public struct DashboardSection: Equatable, Identifiable {
  public let id: String
  public let title: String?
  public let rows: [DashboardRow]

  public init(id: String, title: String?, rows: [DashboardRow]) {
    self.id = id
    self.title = title
    self.rows = rows
  }
}

/// One line of the process list. Its own type rather than a `DashboardRow`: the names need the
/// width the metric rows give to a bar, and there are three numbers beside them.
public struct ProcessRow: Equatable, Identifiable {
  public let id: String
  public let name: String
  /// One decimal, as the TUI shows it.
  public let cpu: String
  /// Watts, or `—` when the energy counter is not readable.
  public let power: String
  public let gpu: String

  public init(id: String, name: String, cpu: String, power: String, gpu: String) {
    self.id = id
    self.name = name
    self.cpu = cpu
    self.power = power
    self.gpu = gpu
  }
}

/// What the panel shows for one sample.
///
/// Pure: the view renders this and nothing here needs a screen, so the rows, the bars and what is
/// left out are testable. A row whose counters are missing is left out rather than shown as zero:
/// a VM has no power, GPU or temperature at all, and a fanless Mac has no fans.
public struct Dashboard: Equatable {
  public let title: String
  /// The chip's core tiers and the total power, as `4E 6P · 12.40 W`.
  public let detail: String?
  public let sections: [DashboardSection]
  /// The busiest processes, as the ABI returns them: busiest first.
  public let processes: [ProcessRow]

  public init(sample: Sample, soc: SocInfo?, processes: [Process] = [], topProcesses: Int = 8) {
    title = soc?.chipName ?? "macmon"
    let parts = [Self.tiers(sample), Self.loadedPower(sample)].compactMap { $0 }
    detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
    sections = [Self.cpu(sample), Self.gpu(sample), Self.power(sample), Self.memory(sample), Self.thermal(sample)]
      .compactMap { $0 }
    self.processes = processes.prefix(max(0, topProcesses)).map(Self.processRow)
  }

  /// One process, formatted. The ABI sorts the list by CPU, so this keeps its order.
  static func processRow(_ process: Process) -> ProcessRow {
    ProcessRow(
      id: "\(process.pid)",
      name: process.name,
      cpu: String(format: "%.1f%%", process.cpuPct),
      power: process.powerW.map(watts) ?? "—",
      gpu: String(format: "%.0f%%", process.gpuPct))
  }

  /// CPU: the whole package, then one row per tier.
  static func cpu(_ sample: Sample) -> DashboardSection? {
    var rows = [
      DashboardRow(
        id: "cpu", label: "CPU", value: percent(sample.cpuScaledRatio),
        fraction: clamped(sample.cpuScaledRatio))
    ]
    for tier in sample.cpuTiers {
      rows.append(
        DashboardRow(
          id: "cpu-\(tier.label)", label: tier.label == "_" ? "all" : tier.label,
          value: percent(tier.scaledRatio), detail: hertz(tier.freqMhz),
          fraction: clamped(tier.scaledRatio), indented: true))
    }
    return DashboardSection(id: "cpu", title: nil, rows: rows)
  }

  /// GPU, left out when every GPU counter reads zero, as in a VM.
  static func gpu(_ sample: Sample) -> DashboardSection? {
    guard sample.gpuFreqMhz > 0 || sample.gpuScaledRatio > 0 || sample.gpuPower > 0 else { return nil }

    let row = DashboardRow(
      id: "gpu", label: "GPU", value: percent(sample.gpuScaledRatio), detail: hertz(sample.gpuFreqMhz),
      fraction: clamped(sample.gpuScaledRatio))
    return DashboardSection(id: "gpu", title: nil, rows: [row])
  }

  /// Power rails, all of them or none: every rail at zero means the counters are missing, not that
  /// the machine drew nothing.
  static func power(_ sample: Sample) -> DashboardSection? {
    let rails = [
      ("CPU", sample.cpuPower), ("GPU", sample.gpuPower), ("ANE", sample.anePower),
      ("DRAM", sample.ramPower), ("GPU RAM", sample.gpuRamPower),
    ]
    let total = sample.allPower
    let system = sample.sysPower
    guard rails.contains(where: { $0.1 != 0 }) || total != 0 || system != 0 else { return nil }

    var rows = rails.map { DashboardRow(id: "power-\($0.0)", label: $0.0, value: watts($0.1)) }
    if total != 0 { rows.append(DashboardRow(id: "power-total", label: "Total", value: watts(total))) }
    if system != 0 { rows.append(DashboardRow(id: "power-system", label: "System", value: watts(system))) }
    return DashboardSection(id: "power", title: "Power", rows: rows)
  }

  /// Memory, and swap when the machine has any configured.
  static func memory(_ sample: Sample) -> DashboardSection {
    var rows = [
      DashboardRow(
        id: "memory-ram", label: "Memory",
        value: usage(sample.memory.ramUsage, of: sample.memory.ramTotal),
        fraction: clamped(sample.memory.ramFraction))
    ]
    if sample.memory.swapTotal > 0 {
      rows.append(
        DashboardRow(
          id: "memory-swap", label: "Swap",
          value: usage(sample.memory.swapUsage, of: sample.memory.swapTotal),
          fraction: clamped(sample.memory.swapFraction)))
    }
    return DashboardSection(id: "memory", title: "Memory", rows: rows)
  }

  /// Temperatures and fans, left out when neither is readable.
  static func thermal(_ sample: Sample) -> DashboardSection? {
    var rows: [DashboardRow] = []
    if let cpu = sample.temp.cpuTempAvg {
      rows.append(DashboardRow(id: "temp-cpu", label: "CPU", value: celsius(cpu)))
    }
    if let gpu = sample.temp.gpuTempAvg {
      rows.append(DashboardRow(id: "temp-gpu", label: "GPU", value: celsius(gpu)))
    }
    for fan in sample.fans {
      rows.append(DashboardRow(id: "fan-\(fan.name)", label: fan.name, value: "\(fan.rpm) rpm"))
    }
    guard !rows.isEmpty else { return nil }
    return DashboardSection(id: "thermal", title: "Temperature", rows: rows)
  }

  /// The core tiers as `4E 6P`, or nil when the machine reports none.
  static func tiers(_ sample: Sample) -> String? {
    guard !sample.cpuTiers.isEmpty else { return nil }
    return sample.cpuTiers
      .map { $0.label == "_" ? "\($0.cores.count) cores" : "\($0.cores.count)\($0.label)" }
      .joined(separator: " ")
  }

  /// The machine's own draw: the system estimate when the counter answers, else CPU + GPU + ANE.
  static func loadedPower(_ sample: Sample) -> String? {
    let value = sample.sysPower != 0 ? sample.sysPower : sample.allPower
    return value != 0 ? watts(value) : nil
  }

  static func percent(_ fraction: Double) -> String {
    "\(Int((clamped(fraction) * 100).rounded()))%"
  }

  static func watts(_ value: Double) -> String {
    String(format: "%.2f W", value)
  }

  static func hertz(_ mhz: UInt32) -> String {
    mhz >= 1000 ? String(format: "%.2f GHz", Double(mhz) / 1000) : "\(mhz) MHz"
  }

  static func celsius(_ value: Double) -> String {
    String(format: "%.1f °C", value)
  }

  /// `18.4 / 64 GB`.
  static func usage(_ used: UInt64, of total: UInt64) -> String {
    let gib = 1_073_741_824.0
    let usedGb = Double(used) / gib
    let totalGb = Double(total) / gib
    let whole = totalGb.rounded()
    let totalText = abs(totalGb - whole) < 0.05 ? String(format: "%.0f", whole) : String(format: "%.1f", totalGb)
    return String(format: "%.1f / %@ GB", usedGb, totalText)
  }

  static func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}
