import XCTest

@testable import MacmonCore

final class DashboardTests: XCTestCase {
  // MARK: - What the panel leaves out

  func testSectionsLeaveOutWhatTheMachineDoesNotReport() {
    // A VM: no GPU counters, no power, no temperatures, no fans.
    let sample = Sample.fixture()
    let dashboard = Dashboard(sample: sample, soc: nil)

    XCTAssertEqual(dashboard.sections.map(\.id), ["cpu", "memory"])
  }

  func testPowerSectionNeedsOneRailThatIsNotZero() {
    XCTAssertNil(Dashboard.power(Sample.fixture()))
    XCTAssertNil(Dashboard.power(Sample.fixture(allPower: 0, sysPower: 0, gpuRamPower: 0)))

    let withPower = Dashboard.power(Sample.fixture(cpuPower: 1.92, allPower: 2.09))?.rows.map(\.label)
    XCTAssertEqual(withPower, ["CPU", "GPU", "ANE", "DRAM", "GPU RAM", "Total"])
  }

  func testGpuSectionNeedsOneGpuCounter() {
    XCTAssertNil(Dashboard.gpu(Sample.fixture()))
    XCTAssertNotNil(Dashboard.gpu(Sample.fixture(gpuScaledRatio: 0.04, gpuFreqMhz: 612)))
    XCTAssertNotNil(Dashboard.gpu(Sample.fixture(gpuPower: 0.1)))
  }

  func testThermalSectionNeedsATemperatureOrAFan() {
    XCTAssertNil(Dashboard.thermal(Sample.fixture()))
    XCTAssertEqual(Dashboard.thermal(Sample.fixture(temp: .init(cpuTempAvg: 44, gpuTempAvg: nil)))?.rows.count, 1)
    XCTAssertEqual(Dashboard.thermal(Sample.fixture(fans: [.init(name: "fan0", rpm: 1200, maxRpm: nil)]))?.rows.count, 1)
  }

  func testSwapRowOnlyWhenSwapIsConfigured() {
    let without = Sample.fixture(memory: .init(ramTotal: 64, ramUsage: 32, swapTotal: 0, swapUsage: 0))
    XCTAssertEqual(Dashboard.memory(without).rows.map(\.id), ["memory-ram"])

    let with = Sample.fixture(memory: .init(ramTotal: 64, ramUsage: 32, swapTotal: 4, swapUsage: 1))
    XCTAssertEqual(Dashboard.memory(with).rows.map(\.id), ["memory-ram", "memory-swap"])
    XCTAssertEqual(Dashboard.memory(with).rows[1].fraction, 0.25)
  }

  // MARK: - Rows and bars

  func testTierRowsFollowTheOverallRow() {
    let oneTier = Dashboard.cpu(Sample.fixture(cpuTiers: [Sample.tier("P", cores: 12)]))
    XCTAssertEqual(oneTier?.rows.map(\.label), ["CPU", "P"])

    let threeTiers = Dashboard.cpu(
      Sample.fixture(cpuTiers: [Sample.tier("E", cores: 4), Sample.tier("P", cores: 6), Sample.tier("S", cores: 2)]))
    XCTAssertEqual(threeTiers?.rows.map(\.label), ["CPU", "E", "P", "S"])
    XCTAssertEqual(threeTiers?.rows.count, 4)
  }

  func testProcessRowsCarryTheirColumns() {
    let processes = [
      Process(
        pid: 412, name: "Hermes", user: "ron", cpuPct: 34.21, memBytes: 3_400_000_000, powerW: 2.31,
        gpuPct: 12.4),
      Process(
        pid: 91, name: "WindowServer", user: "root", cpuPct: 8, memBytes: 1_000_000, powerW: nil,
        gpuPct: 0),
    ]
    let dashboard = Dashboard(sample: Sample.fixture(), soc: nil, processes: processes)

    XCTAssertEqual(dashboard.processes.map(\.name), ["Hermes", "WindowServer"])
    XCTAssertEqual(dashboard.processes[0].cpu, "34.2%")
    XCTAssertEqual(dashboard.processes[0].power, "2.31 W")
    XCTAssertEqual(dashboard.processes[0].gpu, "12%")
    XCTAssertEqual(dashboard.processes[1].power, "—", "an unreadable energy counter is not zero")
  }

  func testOnlyTheBusiestProcessesAreShown() {
    let processes = (0..<12).map { index in
      Process(
        pid: Int32(index), name: "p\(index)", user: "ron", cpuPct: Double(100 - index), memBytes: 0,
        powerW: 0, gpuPct: 0)
    }
    let dashboard = Dashboard(sample: Sample.fixture(), soc: nil, processes: processes)

    XCTAssertEqual(dashboard.processes.count, 8)
    XCTAssertEqual(dashboard.processes.first?.name, "p0", "the ABI's order is kept")
  }

  func testNoProcessListLeavesTheSectionOut() {
    XCTAssertTrue(Dashboard(sample: Sample.fixture(), soc: nil).processes.isEmpty)
  }

  func testTierRowsAreIndentedUnderTheirPackage() {
    let cpu = Dashboard.cpu(Sample.fixture(cpuTiers: [Sample.tier("P", cores: 12)]))
    XCTAssertEqual(cpu?.rows.map(\.indented), [false, true], "the package row, then its tier")
    XCTAssertEqual(Dashboard.memory(Sample.fixture()).rows.map(\.indented), [false])
  }

  func testAnUnknownTierLabelReadsAsAll() {
    XCTAssertEqual(Dashboard.cpu(Sample.fixture(cpuTiers: [Sample.tier("_", cores: 8)]))?.rows[1].label, "all")
  }

  func testBarsUseTheScaledRatioAndStayInRange() {
    XCTAssertEqual(Dashboard.cpu(Sample.fixture(cpuScaledRatio: 0))?.rows[0].fraction, 0)
    XCTAssertEqual(Dashboard.cpu(Sample.fixture(cpuScaledRatio: 0.5))?.rows[0].fraction, 0.5)
    XCTAssertEqual(Dashboard.cpu(Sample.fixture(cpuScaledRatio: 1))?.rows[0].fraction, 1)
    // A counter that overshoots still draws a full bar, not one past the end.
    XCTAssertEqual(Dashboard.cpu(Sample.fixture(cpuScaledRatio: 1.4))?.rows[0].fraction, 1)
    XCTAssertEqual(Dashboard.percent(1.4), "100%")
  }

  func testOnlyMetricRowsCarryABar() {
    XCTAssertNotNil(Dashboard.memory(Sample.fixture()).rows[0].fraction, "memory draws a bar")
    XCTAssertNil(Dashboard.power(Sample.fixture(cpuPower: 1))?.rows[0].fraction, "power does not")
    XCTAssertNil(
      Dashboard.thermal(Sample.fixture(temp: .init(cpuTempAvg: 44, gpuTempAvg: nil)))?.rows[0].fraction,
      "temperature does not")
  }

  // MARK: - Text

  func testHeaderIsTheChipItsTiersAndItsPower() {
    let sample = Sample.fixture(
      cpuTiers: [Sample.tier("E", cores: 4), Sample.tier("P", cores: 12)], cpuPower: 1.92, allPower: 2.09, sysPower: 12.4)
    let dashboard = Dashboard(sample: sample, soc: SocInfo(macModel: "Mac17,14", chipName: "Apple M5 Max", memoryGb: 64))

    XCTAssertEqual(dashboard.title, "Apple M5 Max")
    XCTAssertEqual(dashboard.detail, "4E 12P · 12.40 W")
  }

  func testHeaderWithoutMachineInformationFallsBack() {
    let dashboard = Dashboard(sample: Sample.fixture(cpuTiers: []), soc: nil)
    XCTAssertEqual(dashboard.title, "macmon")
    XCTAssertNil(dashboard.detail)
  }

  func testValueFormatting() {
    XCTAssertEqual(Dashboard.percent(0.12), "12%")
    XCTAssertEqual(Dashboard.percent(0.999), "100%")
    XCTAssertEqual(Dashboard.hertz(612), "612 MHz")
    XCTAssertEqual(Dashboard.hertz(2154), "2.15 GHz")
    XCTAssertEqual(Dashboard.watts(1.9236), "1.92 W")
    XCTAssertEqual(Dashboard.celsius(44.0347), "44.0 °C")
    XCTAssertEqual(Dashboard.usage(19_756_577_844, of: 68_719_476_736), "18.4 / 64 GB")
  }

  // MARK: - Fixtures
}
