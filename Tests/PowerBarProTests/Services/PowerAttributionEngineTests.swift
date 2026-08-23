import XCTest
@testable import PowerBarPro

final class PowerAttributionEngineTests: XCTestCase {

    var engine: PowerAttributionEngine!

    override func setUp() {
        super.setUp()
        engine = PowerAttributionEngine()
    }

    // MARK: - Basic Attribution

    func testAttribute_emptyProcesses_returnsEmpty() {
        let budget = ComponentPowerBudget(cpuW: 5, dramW: 1, gpuW: 2, storageW: 0.1, fabricW: 1, systemTotalW: 15)
        let result = engine.attribute(processes: [], budget: budget)
        XCTAssertTrue(result.isEmpty)
    }

    func testAttribute_singleProcess_getsAllComponentPower() {
        let budget = ComponentPowerBudget(cpuW: 5, dramW: 1, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Safari", pids: [100], cpuEnergyNJ: 1000, memoryBytes: 500_000_000, gpuTimeNS: 0, diskIOBytes: 0)
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        XCTAssertEqual(result.count, 1)
        // Single process gets 100% of CPU budget
        XCTAssertEqual(result[0].cpuWatts, 5.0, accuracy: 0.01)
        // Single process gets 100% of DRAM budget
        XCTAssertEqual(result[0].dramWatts, 1.0, accuracy: 0.01)
    }

    func testAttribute_twoProcesses_cpuProportional() {
        let budget = ComponentPowerBudget(cpuW: 10, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Heavy", pids: [1], cpuEnergyNJ: 900, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
            ProcessUsageData(name: "Light", pids: [2], cpuEnergyNJ: 100, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        // Heavy = 90% of 10W = 9W
        let heavy = result.first(where: { $0.name == "Heavy" })!
        XCTAssertEqual(heavy.cpuWatts, 9.0, accuracy: 0.01)

        // Light = 10% of 10W = 1W
        let light = result.first(where: { $0.name == "Light" })!
        XCTAssertEqual(light.cpuWatts, 1.0, accuracy: 0.01)
    }

    func testAttribute_dramProportionalToMemory() {
        let budget = ComponentPowerBudget(cpuW: 0, dramW: 2, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "MemHog", pids: [1], cpuEnergyNJ: 0, memoryBytes: 4_000_000_000, gpuTimeNS: 0, diskIOBytes: 0),
            ProcessUsageData(name: "Tiny", pids: [2], cpuEnergyNJ: 0, memoryBytes: 1_000_000_000, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        let memHog = result.first(where: { $0.name == "MemHog" })!
        // 4GB/5GB = 80% of 2W = 1.6W
        XCTAssertEqual(memHog.dramWatts, 1.6, accuracy: 0.01)

        let tiny = result.first(where: { $0.name == "Tiny" })!
        // 1GB/5GB = 20% of 2W = 0.4W
        XCTAssertEqual(tiny.dramWatts, 0.4, accuracy: 0.01)
    }

    func testAttribute_fabricDistribution() {
        // Fabric should be distributed: 70% CPU, 20% DRAM, 10% GPU
        let budget = ComponentPowerBudget(cpuW: 0, dramW: 0, gpuW: 0, storageW: 0, fabricW: 10, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "App", pids: [1], cpuEnergyNJ: 1000, memoryBytes: 1_000_000, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        // CPU gets 70% of 10W fabric = 7W
        XCTAssertEqual(result[0].cpuWatts, 7.0, accuracy: 0.01)
        // DRAM gets 20% of 10W fabric = 2W
        XCTAssertEqual(result[0].dramWatts, 2.0, accuracy: 0.01)
    }

    func testAttribute_percentOfSystem() {
        let budget = ComponentPowerBudget(cpuW: 5, dramW: 1, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 20)
        let processes = [
            ProcessUsageData(name: "App", pids: [1], cpuEnergyNJ: 1000, memoryBytes: 500_000, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        // Total = 5W + 1W = 6W. System = 20W. Percent = 30%
        XCTAssertEqual(result[0].percentOfSystem, 30.0, accuracy: 0.5)
    }

    func testAttribute_sortedByTotalWattsDescending() {
        let budget = ComponentPowerBudget(cpuW: 10, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Small", pids: [1], cpuEnergyNJ: 100, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
            ProcessUsageData(name: "Big", pids: [2], cpuEnergyNJ: 900, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        XCTAssertEqual(result[0].name, "Big")
        XCTAssertEqual(result[1].name, "Small")
    }

    // MARK: - Calibration Coefficients

    func testGlobalCoefficient_appliedToAll() {
        engine.globalCoefficient = 2.0

        let budget = ComponentPowerBudget(cpuW: 10, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "App", pids: [1], cpuEnergyNJ: 1000, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        // 10W CPU * 2.0 coefficient = 20W
        XCTAssertEqual(result[0].cpuWatts, 20.0, accuracy: 0.01)
    }

    func testAppCoefficient_overridesGlobal() {
        engine.globalCoefficient = 2.0
        engine.appCoefficients["Special"] = 5.0

        let budget = ComponentPowerBudget(cpuW: 10, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Special", pids: [1], cpuEnergyNJ: 500, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
            ProcessUsageData(name: "Normal", pids: [2], cpuEnergyNJ: 500, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        let special = result.first(where: { $0.name == "Special" })!
        let normal = result.first(where: { $0.name == "Normal" })!

        // Special: 5W * 5.0 = 25W
        XCTAssertEqual(special.cpuWatts, 25.0, accuracy: 0.01)
        // Normal: 5W * 2.0 = 10W
        XCTAssertEqual(normal.cpuWatts, 10.0, accuracy: 0.01)
    }

    // MARK: - rawCpuWatts

    func testRawCpuWatts_notAffectedByCoefficient() {
        engine.globalCoefficient = 3.0

        let budget = ComponentPowerBudget(cpuW: 10, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "App", pids: [1], cpuEnergyNJ: 1000, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        // Raw should be unscaled: 100% of 10W CPU = 10W
        XCTAssertEqual(result[0].rawCpuWatts, 10.0, accuracy: 0.01)
        // Attributed should be scaled: 10W * 3.0 = 30W
        XCTAssertEqual(result[0].cpuWatts, 30.0, accuracy: 0.01)
    }

    // MARK: - Correction Factor

    func testAverageCorrectionFactor_noData() {
        let factor = engine.averageCorrectionFactor(attributed: [])
        XCTAssertEqual(factor, 1.0, accuracy: 0.001)
    }

    func testAverageCorrectionFactor_withData() {
        let attributed = [
            AttributedPower(id: "A", name: "A", pids: [1], cpuWatts: 5, dramWatts: 2, gpuWatts: 1, storageWatts: 0, percentOfSystem: 50, memoryBytes: 0, pidCount: 1, rawCpuWatts: 2),
            // total=8, raw=2, ratio=4
        ]

        let factor = engine.averageCorrectionFactor(attributed: attributed)
        XCTAssertEqual(factor, 4.0, accuracy: 0.01)
    }

    // MARK: - Edge Cases

    func testAttribute_zeroCpuEnergy_noDiv0() {
        let budget = ComponentPowerBudget(cpuW: 10, dramW: 1, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Idle", pids: [1], cpuEnergyNJ: 0, memoryBytes: 100, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)
        XCTAssertEqual(result[0].cpuWatts, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[0].dramWatts, 1.0, accuracy: 0.01) // Gets all DRAM
    }

    func testAttribute_gpuAttribution() {
        let budget = ComponentPowerBudget(cpuW: 0, dramW: 0, gpuW: 10, storageW: 0, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Renderer", pids: [1], cpuEnergyNJ: 0, memoryBytes: 0, gpuTimeNS: 800, diskIOBytes: 0),
            ProcessUsageData(name: "Editor", pids: [2], cpuEnergyNJ: 0, memoryBytes: 0, gpuTimeNS: 200, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        let renderer = result.first(where: { $0.name == "Renderer" })!
        XCTAssertEqual(renderer.gpuWatts, 8.0, accuracy: 0.01) // 80% of 10W

        let editor = result.first(where: { $0.name == "Editor" })!
        XCTAssertEqual(editor.gpuWatts, 2.0, accuracy: 0.01) // 20% of 10W
    }

    func testAttribute_storageAttribution() {
        let budget = ComponentPowerBudget(cpuW: 0, dramW: 0, gpuW: 0, storageW: 0.5, fabricW: 0, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "Writer", pids: [1], cpuEnergyNJ: 0, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 1000),
            ProcessUsageData(name: "Reader", pids: [2], cpuEnergyNJ: 0, memoryBytes: 0, gpuTimeNS: 0, diskIOBytes: 500),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        let writer = result.first(where: { $0.name == "Writer" })!
        // 1000/1500 = 66.7% of 0.5W ≈ 0.333W
        XCTAssertEqual(writer.storageWatts, 0.333, accuracy: 0.01)
    }

    func testAttribute_allComponentsCombined() {
        let budget = ComponentPowerBudget(cpuW: 5, dramW: 1, gpuW: 3, storageW: 0.2, fabricW: 2, systemTotalW: 15)
        let processes = [
            ProcessUsageData(name: "HeavyApp", pids: [1], cpuEnergyNJ: 1000, memoryBytes: 2_000_000_000,
                             gpuTimeNS: 500, diskIOBytes: 800),
        ]

        let result = engine.attribute(processes: processes, budget: budget)

        XCTAssertEqual(result.count, 1)
        let app = result[0]
        // Should have contributions from ALL components
        XCTAssertGreaterThan(app.cpuWatts, 0)
        XCTAssertGreaterThan(app.dramWatts, 0)
        XCTAssertGreaterThan(app.gpuWatts, 0)
        XCTAssertGreaterThan(app.storageWatts, 0)
        XCTAssertGreaterThan(app.totalWatts, app.cpuWatts) // Total > CPU alone
    }

    func testAttribute_zeroSystemPower_zeroPercent() {
        let budget = ComponentPowerBudget(cpuW: 0, dramW: 0, gpuW: 0, storageW: 0, fabricW: 0, systemTotalW: 0)
        let processes = [
            ProcessUsageData(name: "App", pids: [1], cpuEnergyNJ: 100, memoryBytes: 100, gpuTimeNS: 0, diskIOBytes: 0),
        ]

        let result = engine.attribute(processes: processes, budget: budget)
        XCTAssertEqual(result[0].percentOfSystem, 0.0, accuracy: 0.001)
    }
}

// MARK: - ComponentPowerBudget Tests

final class ComponentPowerBudgetTests: XCTestCase {

    func testFromSystemMetrics() {
        let metrics = TestData.sampleMetrics()
        let budget = ComponentPowerBudget.from(metrics)

        XCTAssertEqual(budget.cpuW, metrics.soc.cpuW, accuracy: 0.001)
        XCTAssertEqual(budget.dramW, metrics.soc.dramW, accuracy: 0.001)
        XCTAssertEqual(budget.gpuW, metrics.soc.gpuW, accuracy: 0.001)
        XCTAssertEqual(budget.storageW, metrics.ssdPowerW, accuracy: 0.001)
        XCTAssertEqual(budget.fabricW, metrics.soc.fabricW, accuracy: 0.001)
        XCTAssertEqual(budget.systemTotalW, metrics.sysPowerW, accuracy: 0.001)
    }
}
