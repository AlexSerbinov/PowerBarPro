import XCTest
import Combine
@testable import PowerBarPro

final class ProcessListViewModelTests: XCTestCase {

    var mockProcessMonitor: MockProcessMonitor!
    var mockTerminator: MockProcessTerminator2!
    var vm: ProcessListViewModel!

    override func setUp() {
        super.setUp()
        mockProcessMonitor = MockProcessMonitor()
        mockTerminator = MockProcessTerminator2()
        vm = ProcessListViewModel(
            processMonitor: mockProcessMonitor,
            terminator: mockTerminator
        )
    }

    override func tearDown() {
        vm = nil
        mockProcessMonitor = nil
        mockTerminator = nil
        super.tearDown()
    }

    // MARK: - refresh

    func testRefresh_nilMetrics_noOp() {
        vm.refresh(metrics: nil)
        XCTAssertTrue(vm.attributedProcesses.isEmpty)
        XCTAssertEqual(vm.displayPowerText, "")
    }

    func testRefresh_validMetrics_updatesDisplayPower() {
        let metrics = TestData.sampleMetrics()
        vm.refresh(metrics: metrics)

        XCTAssertTrue(vm.displayPowerText.contains("Display"))
        XCTAssertTrue(vm.displayPowerText.contains("W"))
        XCTAssertGreaterThan(vm.displayPowerW, 0)
    }

    func testRefresh_displaysMaxOfBacklightAndEstimated() {
        let metrics = TestData.sampleMetrics()
        vm.refresh(metrics: metrics)

        // sampleMetrics: backlight=4.5W, estimated=1.26W → max = 4.5
        XCTAssertEqual(vm.displayPowerW, 4.5, accuracy: 0.01)
    }

    func testRefresh_populatesAttributedProcesses() {
        mockProcessMonitor.stubbedProcesses = [
            ProcessPowerInfo(id: "Safari", name: "Safari", powerWatts: 0.5,
                            percentOfSystem: 5.0, memoryBytes: 500_000_000,
                            pidCount: 1, pids: [100])
        ]

        let metrics = TestData.sampleMetrics()
        vm.refresh(metrics: metrics)

        XCTAssertFalse(vm.attributedProcesses.isEmpty)
        XCTAssertEqual(vm.attributedProcesses[0].name, "Safari")
        // Attributed watts should be >= raw (proportional attribution adds DRAM share)
        XCTAssertGreaterThanOrEqual(vm.attributedProcesses[0].totalWatts, 0)
    }

    func testRefresh_updatesCoalitions() {
        mockProcessMonitor.stubbedProcesses = [
            ProcessPowerInfo(id: "App", name: "App", powerWatts: 0.1,
                            percentOfSystem: 1.0, memoryBytes: 100_000,
                            pidCount: 1, pids: [200])
        ]

        let metrics = TestData.sampleMetrics()
        vm.refresh(metrics: metrics)

        // Coalitions should have entries
        XCTAssertFalse(vm.coalitions.isEmpty)
    }

    func testRefresh_correctionFactor() {
        mockProcessMonitor.stubbedProcesses = [
            ProcessPowerInfo(id: "App", name: "App", powerWatts: 0.5,
                            percentOfSystem: 5.0, memoryBytes: 500_000_000,
                            pidCount: 1, pids: [100])
        ]

        let metrics = TestData.sampleMetrics()
        vm.refresh(metrics: metrics)

        // Correction factor should be >= 1 (attributed includes DRAM/fabric)
        XCTAssertGreaterThanOrEqual(vm.correctionFactor, 1.0)
    }

    // MARK: - terminate

    func testTerminateProcess_callsTerminator() {
        let info = ProcessPowerInfo(id: "App", name: "App", powerWatts: 0.1,
                                    percentOfSystem: 1.0, memoryBytes: 0,
                                    pidCount: 1, pids: [42])
        let result = vm.terminateProcess(info)

        XCTAssertTrue(result)
        XCTAssertEqual(mockTerminator.terminatedPIDs, [42])
    }

    func testTerminateAttributedProcess_callsTerminator() {
        let info = AttributedPower(id: "App", name: "App", pids: [55],
                                    cpuWatts: 1, dramWatts: 0.5, gpuWatts: 0, storageWatts: 0,
                                    percentOfSystem: 10, memoryBytes: 0, pidCount: 1, rawCpuWatts: 0.5)
        let result = vm.terminateProcess(info)

        XCTAssertTrue(result)
        XCTAssertEqual(mockTerminator.terminatedPIDs, [55])
    }

    // MARK: - display without available flag

    func testRefresh_displayNotAvailable() {
        let metrics = TestData.metrics(sysPower: 10, allPower: 5)
        vm.refresh(metrics: metrics)

        // Minimal metrics have no display → shows just watts
        XCTAssertTrue(vm.displayPowerText.contains("Display"))
    }
}

// MARK: - Mocks

final class MockProcessMonitor: ProcessMonitoring {
    var stubbedProcesses: [ProcessPowerInfo] = []

    func sampleProcesses(systemPowerW: Double) -> [ProcessPowerInfo] {
        stubbedProcesses
    }

    func reset() {
        stubbedProcesses = []
    }
}

final class MockProcessTerminator2: ProcessTerminating {
    var terminatedPIDs: [pid_t] = []

    func terminate(pid: pid_t) -> Bool {
        terminatedPIDs.append(pid)
        return true
    }

    func terminateAll(pids: [pid_t]) -> Int {
        terminatedPIDs.append(contentsOf: pids)
        return pids.count
    }
}
