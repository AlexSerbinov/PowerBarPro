import Foundation
@testable import PowerBarPro

/// Mock battery monitor for testing.
final class MockBatteryMonitor: BatteryMonitoring {

    var stubbedBatteryState: BatteryState?
    var stubbedRemainingTime: TimeInterval?
    private(set) var calculateRemainingTimeCallCount = 0
    private(set) var lastCalculateArgs: (battery: BatteryState, power: Double)?

    func getBatteryState() -> BatteryState? {
        stubbedBatteryState
    }

    func calculateRemainingTime(battery: BatteryState, averagePowerW: Double) -> TimeInterval? {
        calculateRemainingTimeCallCount += 1
        lastCalculateArgs = (battery: battery, power: averagePowerW)
        return stubbedRemainingTime
    }
}
