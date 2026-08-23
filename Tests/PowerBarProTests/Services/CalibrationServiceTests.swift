import XCTest
import Combine
@testable import PowerBarPro

final class CalibrationServiceTests: XCTestCase {

    var mockTerminator: MockProcessTerminator!
    var service: CalibrationService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockTerminator = MockProcessTerminator()
        // Use fast config for tests
        let config = CalibrationService.Config(
            baselineDuration: 2,
            postBaselineDuration: 2,
            maxSettleTime: 5,
            settleVarianceThreshold: 5.0,
            settleWindowSeconds: 1,
            emaAlpha: 0.5,
            discardInitialSeconds: 0.5
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calibration_test_\(UUID().uuidString).json")
        service = CalibrationService(processTerminator: mockTerminator, config: config, storageURL: tempURL)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        service = nil
        mockTerminator = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_idle() {
        XCTAssertEqual(service.state, .idle)
    }

    func testInitialStore_defaults() {
        XCTAssertEqual(service.store.globalCoefficient, 1.0)
        XCTAssertTrue(service.store.appCoefficients.isEmpty)
    }

    // MARK: - Start Calibration

    func testStartCalibration_changesState() {
        service.startCalibration(appName: "TestApp", pids: [123], currentRusagePowerW: 0.08)

        if case .measuringBaseline = service.state {
            // OK
        } else {
            XCTFail("Expected measuringBaseline, got \(service.state)")
        }
    }

    func testStartCalibration_doubleCall_ignored() {
        service.startCalibration(appName: "App1", pids: [1], currentRusagePowerW: 0.1)
        service.startCalibration(appName: "App2", pids: [2], currentRusagePowerW: 0.2)

        // Should still be calibrating App1
        if case .measuringBaseline = service.state {
            // OK - second call was ignored
        } else {
            XCTFail("Expected measuringBaseline")
        }
    }

    // MARK: - Feed Power Readings

    func testFeedPower_duringBaseline_updatesProgress() {
        service.startCalibration(appName: "App", pids: [100], currentRusagePowerW: 0.08)

        service.feedPowerReading(15.0)

        if case .measuringBaseline(let progress) = service.state {
            XCTAssertGreaterThanOrEqual(progress, 0.0)
        } else {
            XCTFail("Expected measuringBaseline")
        }
    }

    func testFeedPower_whenIdle_ignored() {
        // Should not crash
        service.feedPowerReading(15.0)
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - Full Calibration Cycle (fast)

    func testFullCalibrationCycle() {
        let exp = expectation(description: "calibration completed")

        service.$state
            .sink { state in
                if case .completed(let result) = state {
                    XCTAssertEqual(result.appName, "TestApp")
                    XCTAssertGreaterThan(result.baselinePowerW, 0)
                    XCTAssertGreaterThan(result.coefficient, 0)
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)

        service.startCalibration(appName: "TestApp", pids: [123], currentRusagePowerW: 0.08)

        // Simulate power readings over time
        // Baseline: system at 15W
        let baselineTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            switch self.service.state {
            case .measuringBaseline:
                self.service.feedPowerReading(15.0 + Double.random(in: -0.3...0.3))
            case .settling:
                // System drops to ~12W after app killed
                self.service.feedPowerReading(12.0 + Double.random(in: -0.2...0.2))
            case .measuringPostBaseline:
                self.service.feedPowerReading(12.0 + Double.random(in: -0.2...0.2))
            case .completed:
                timer.invalidate()
            case .failed:
                timer.invalidate()
            default:
                self.service.feedPowerReading(13.0)
            }
        }
        RunLoop.main.add(baselineTimer, forMode: .common)

        wait(for: [exp], timeout: 15.0)
        baselineTimer.invalidate()
    }

    // MARK: - Coefficient Retrieval

    func testCoefficient_defaultIsGlobal() {
        XCTAssertEqual(service.coefficient(for: "Unknown"), 1.0)
    }

    func testCoefficient_afterCalibration_returnsStored() {
        // Manually add a calibration result
        let result = CalibrationResult(
            appName: "Safari",
            coefficient: 3.5,
            baselinePowerW: 15.0,
            postBaselinePowerW: 12.0,
            deltaPowerW: 3.0,
            rusagePowerW: 0.86,
            timestamp: Date(),
            settleTimeSeconds: 30,
            variancePct: 3.0
        )
        service.store.appCoefficients["Safari"] = result

        XCTAssertEqual(service.coefficient(for: "Safari"), 3.5, accuracy: 0.01)
    }

    // MARK: - Cancel

    func testCancel_resetsToIdle() {
        service.startCalibration(appName: "App", pids: [1], currentRusagePowerW: 0.1)
        service.cancel()
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - Variance Calculation

    func testVariancePct_stableReadings() {
        let values = [10.0, 10.1, 9.9, 10.0, 10.0]
        let variance = CalibrationService.variancePct(values)
        XCTAssertLessThan(variance, 2.0) // Very stable
    }

    func testVariancePct_unstableReadings() {
        let values = [5.0, 15.0, 3.0, 20.0, 8.0]
        let variance = CalibrationService.variancePct(values)
        XCTAssertGreaterThan(variance, 30.0) // Very unstable
    }

    func testVariancePct_singleValue() {
        let variance = CalibrationService.variancePct([10.0])
        XCTAssertEqual(variance, 100.0) // Not enough data
    }

    func testVariancePct_emptyArray() {
        let variance = CalibrationService.variancePct([])
        XCTAssertEqual(variance, 100.0)
    }

    // MARK: - CalibrationResult Reliability

    func testCalibrationResult_reliable() {
        let result = CalibrationResult(
            appName: "App", coefficient: 3.0,
            baselinePowerW: 15.0, postBaselinePowerW: 12.0,
            deltaPowerW: 3.0, rusagePowerW: 1.0,
            timestamp: Date(), settleTimeSeconds: 30, variancePct: 3.0
        )
        XCTAssertTrue(result.isReliable)
    }

    func testCalibrationResult_unreliable_highVariance() {
        let result = CalibrationResult(
            appName: "App", coefficient: 3.0,
            baselinePowerW: 15.0, postBaselinePowerW: 12.0,
            deltaPowerW: 3.0, rusagePowerW: 1.0,
            timestamp: Date(), settleTimeSeconds: 30, variancePct: 15.0
        )
        XCTAssertFalse(result.isReliable)
    }

    func testCalibrationResult_unreliable_extremeCoefficient() {
        let result = CalibrationResult(
            appName: "App", coefficient: 200.0,
            baselinePowerW: 15.0, postBaselinePowerW: 12.0,
            deltaPowerW: 3.0, rusagePowerW: 0.015,
            timestamp: Date(), settleTimeSeconds: 30, variancePct: 3.0
        )
        XCTAssertFalse(result.isReliable)
    }
}

// MARK: - Mock Process Terminator

final class MockProcessTerminator: ProcessTerminating {
    private(set) var terminatedPIDs: [pid_t] = []

    func terminate(pid: pid_t) -> Bool {
        terminatedPIDs.append(pid)
        return true
    }

    func terminateAll(pids: [pid_t]) -> Int {
        terminatedPIDs.append(contentsOf: pids)
        return pids.count
    }
}
