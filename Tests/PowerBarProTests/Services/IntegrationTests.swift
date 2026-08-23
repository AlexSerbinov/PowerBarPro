import XCTest
import Combine
@testable import PowerBarPro

/// Integration and smoke tests that verify wiring between layers.
final class IntegrationTests: XCTestCase {

    // MARK: - PowerDisplayViewModel + PowerAggregator integration

    func testPowerDisplayVM_powerValueForMode_instant() {
        let mock = MockPowerMonitor()
        let aggregator = PowerAggregator()
        let settings = MockSettingsStore(displayMode: .instant)
        let vm = PowerDisplayViewModel(
            powerMonitor: mock,
            aggregator: aggregator,
            settings: settings
        )

        // No metrics → nil
        XCTAssertNil(vm.powerValue(for: .instant))

        // Simulate metrics arriving
        mock.startMonitoring()
        let metrics = TestData.metrics(sysPower: 15.0)
        mock.emit(metrics)

        let exp = expectation(description: "metrics arrive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Now we should have a value
            let value = vm.powerValue(for: .instant)
            XCTAssertNotNil(value)
            XCTAssertEqual(value!, 15.0, accuracy: 0.001)

            // Also test for average mode
            let avgValue = vm.powerValue(for: .average(seconds: 0))
            XCTAssertNotNil(avgValue)
            XCTAssertEqual(avgValue!, 15.0, accuracy: 0.001)

            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - MenuBuilder: updateBatteryModeCheckmarks

    func testMenuBuilder_updateBatteryModeCheckmarks() {
        let builder = MenuBuilder()
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        // Change battery mode to instant
        builder.updateBatteryModeCheckmarks(mode: .instant)

        let submenu = builder.batteryItem?.submenu
        XCTAssertNotNil(submenu)

        let instantItem = submenu?.items.first(where: { $0.tag == -1 })
        XCTAssertEqual(instantItem?.state, .on)

        let fiveMinItem = submenu?.items.first(where: { $0.tag == 300 })
        XCTAssertEqual(fiveMinItem?.state, .off)
    }

    func testMenuBuilder_updateBatteryModeCheckmarks_average() {
        let builder = MenuBuilder()
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        builder.updateBatteryModeCheckmarks(mode: .average(seconds: 60))

        let submenu = builder.batteryItem?.submenu
        let instantItem = submenu?.items.first(where: { $0.tag == -1 })
        XCTAssertEqual(instantItem?.state, .off)

        let minuteItem = submenu?.items.first(where: { $0.tag == 60 })
        XCTAssertEqual(minuteItem?.state, .on)
    }

    // MARK: - Edge cases: Negative & NaN values

    func testPowerAggregator_negativePowerValues() {
        let agg = PowerAggregator()
        agg.record(PowerReading(allPower: -5, sysPower: -3))
        agg.record(PowerReading(allPower: 10, sysPower: 8))

        let avg = agg.average(for: 0)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!.sysPower, 2.5, accuracy: 0.001) // (-3 + 8) / 2
        XCTAssertEqual(avg!.allPower, 2.5, accuracy: 0.001) // (-5 + 10) / 2
    }

    func testBatteryState_negativeCapacity() {
        let state = BatteryState(
            isCharging: false,
            externalConnected: false,
            currentCapacity: -100,
            voltage: 12000
        )
        // Negative capacity × positive voltage = negative Wh
        XCTAssertLessThan(state.remainingEnergyWh, 0)
    }

    func testFormatters_negativePower() {
        XCTAssertEqual(Formatters.power(-5.3), "-5.3W")
    }

    func testFormatters_negativeTime() {
        // Negative time produces "0m" (truncates to 0)
        let result = Formatters.remainingTime(-60)
        XCTAssertEqual(result, "0m")
    }
}
