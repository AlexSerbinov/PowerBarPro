import XCTest
import Combine
@testable import PowerBarPro

final class PowerDisplayViewModelTests: XCTestCase {

    var mockPower: MockPowerMonitor!
    var aggregator: PowerAggregator!
    var mockSettings: MockSettingsStore!
    var vm: PowerDisplayViewModel!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockPower = MockPowerMonitor()
        aggregator = PowerAggregator()
        mockSettings = MockSettingsStore(displayMode: .instant)
        vm = PowerDisplayViewModel(
            powerMonitor: mockPower,
            aggregator: aggregator,
            settings: mockSettings
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        vm = nil
        mockPower = nil
        aggregator = nil
        mockSettings = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_loading() {
        XCTAssertEqual(vm.statusText, "Loading...")
        XCTAssertFalse(vm.isError)
    }

    // MARK: - Metrics Update

    func testMetricsUpdate_updatesStatusText() {
        let exp = expectation(description: "status updated")

        // Must start monitoring first so isRunning = true
        mockPower.startMonitoring()

        vm.$statusText
            .dropFirst()
            .first(where: { $0.contains("W") })
            .sink { text in
                XCTAssertEqual(text, "12.1W")
                exp.fulfill()
            }
            .store(in: &cancellables)

        mockPower.emit(TestData.sampleMetrics())

        wait(for: [exp], timeout: 2.0)
    }

    func testMetricsUpdate_updatesDetailsText() {
        let exp = expectation(description: "details updated")

        mockPower.startMonitoring()

        vm.$detailsText
            .dropFirst()
            .first(where: { $0 != "Power Details" })
            .sink { text in
                XCTAssertTrue(text.contains("System: 12.1W"))
                exp.fulfill()
            }
            .store(in: &cancellables)

        mockPower.emit(TestData.sampleMetrics())

        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Error State

    func testError_showsErrorStatus() {
        let exp = expectation(description: "error state")

        vm.$isError
            .dropFirst()
            .first(where: { $0 == true })
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        mockPower.emitError(.macmonNotFound)

        wait(for: [exp], timeout: 2.0)
    }

    func testError_statusTextShowsError() {
        let exp = expectation(description: "error text")

        vm.$statusText
            .dropFirst()
            .first(where: { $0 == "Error" })
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        mockPower.emitError(.macmonNotFound)

        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Stopped State

    func testStoppedState_showsStopped() {
        let exp = expectation(description: "stopped")

        vm.$statusText
            .dropFirst()
            .first(where: { $0 == "Stopped" })
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        mockPower.stopMonitoring()

        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - currentPowerValue

    func testCurrentPowerValue_noMetrics_returnsNil() {
        XCTAssertNil(vm.currentPowerValue())
    }

    // MARK: - Settings → PowerMonitor wiring

    func testIntervalChange_triggersMonitorUpdate() {
        let exp = expectation(description: "interval forwarded")

        // Give the subscription time to establish, then change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mockSettings.updateIntervalMs = 500
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(self.mockPower.lastSetInterval, 500)
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2.0)
    }
}
