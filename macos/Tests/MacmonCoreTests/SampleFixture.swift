import Foundation

@testable import MacmonCore

/// Sample fixtures for the tests: every field the panel reads, with the machine-specific ones left
/// at a quiet default. A test sets only what it is about.
extension Sample {
  static func fixture(
    timestamp: Double = 1_791_836_540,
    cpuScaledRatio: Double = 0.12,
    cpuTiers: [Sample.Tier]? = nil,
    cpuPower: Double = 0,
    gpuScaledRatio: Double = 0,
    gpuFreqMhz: UInt32 = 0,
    gpuPower: Double = 0,
    anePower: Double = 0,
    allPower: Double = 0,
    sysPower: Double = 0,
    ramPower: Double = 0,
    gpuRamPower: Double = 0,
    temp: Sample.Temperature = .init(cpuTempAvg: nil, gpuTempAvg: nil),
    memory: Sample.Memory = .init(
      ramTotal: 68_719_476_736, ramUsage: 34_359_738_368, swapTotal: 0, swapUsage: 0),
    fans: [Sample.Fan] = []
  ) -> Sample {
    Sample(
      timestamp: timestamp, cpuScaledRatio: cpuScaledRatio, cpuActiveRatio: 0.2,
      cpuTiers: cpuTiers ?? [tier("P", cores: 12)], cpuPower: cpuPower, gpuScaledRatio: gpuScaledRatio,
      gpuFreqMhz: gpuFreqMhz, gpuActiveRatio: 0, gpuPower: gpuPower, anePower: anePower,
      allPower: allPower, sysPower: sysPower, ramPower: ramPower, gpuRamPower: gpuRamPower,
      temp: temp, memory: memory, fans: fans)
  }

  /// One tier with `cores` identical cores.
  static func tier(_ label: String, cores: Int) -> Sample.Tier {
    Sample.Tier(
      label: label, freqMhz: 2154, scaledRatio: 0.12, activeRatio: 0.2,
      cores: (0..<cores).map {
        Sample.Core(dieId: 0, coreId: $0, freqMhz: 2154, scaledRatio: 0.1, activeRatio: 0.2)
      })
  }
}
