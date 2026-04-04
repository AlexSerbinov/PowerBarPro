import XCTest
@testable import PowerBarPro

final class BatteryStateTests: XCTestCase {

    // MARK: - remainingEnergyWh

    func testRemainingEnergyWh_typical() {
        let state = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        XCTAssertEqual(state.remainingEnergyWh, 60.0, accuracy: 0.001)
    }

    func testRemainingEnergyWh_low() {
        let state = TestData.batteryOnBattery(capacity: 500, voltage: 11000)
        XCTAssertEqual(state.remainingEnergyWh, 5.5, accuracy: 0.001)
    }

    func testRemainingEnergyWh_full() {
        let state = TestData.batteryCharging(capacity: 7200, voltage: 12800)
        XCTAssertEqual(state.remainingEnergyWh, 92.16, accuracy: 0.001)
    }

    func testRemainingEnergyWh_zeroCapacity() {
        let state = BatteryState(isCharging: false, externalConnected: false,
                                  currentCapacity: 0, voltage: 12000)
        XCTAssertEqual(state.remainingEnergyWh, 0.0, accuracy: 0.001)
    }

    func testRemainingEnergyWh_zeroVoltage() {
        let state = BatteryState(isCharging: false, externalConnected: false,
                                  currentCapacity: 5000, voltage: 0)
        XCTAssertEqual(state.remainingEnergyWh, 0.0, accuracy: 0.001)
    }

    // MARK: - isOnBatteryPower

    func testIsOnBatteryPower_disconnected() {
        let state = TestData.batteryOnBattery()
        XCTAssertTrue(state.isOnBatteryPower)
    }

    func testIsOnBatteryPower_externalConnected() {
        let state = TestData.batteryCharging()
        XCTAssertFalse(state.isOnBatteryPower)
    }

    func testIsOnBatteryPower_connectedNotCharging() {
        let state = BatteryState(isCharging: false, externalConnected: true,
                                  currentCapacity: 7000, voltage: 12800)
        XCTAssertFalse(state.isOnBatteryPower)
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        let b = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        XCTAssertEqual(a, b)
    }

    func testNotEqual_differentCapacity() {
        let a = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        let b = TestData.batteryOnBattery(capacity: 3000, voltage: 12000)
        XCTAssertNotEqual(a, b)
    }
}
