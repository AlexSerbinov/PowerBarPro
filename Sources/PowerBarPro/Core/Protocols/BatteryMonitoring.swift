import Foundation

/// Abstraction over battery hardware data (ioreg).
/// Implementations: `SystemBatteryService` (production), `MockBatteryMonitor` (tests).
protocol BatteryMonitoring {
    /// Read current battery state. Returns `nil` if no battery or data unavailable.
    func getBatteryState() -> BatteryState?

    /// Calculate remaining battery time based on current energy and power draw.
    /// Returns `nil` if on external power or power too low for reliable estimate.
    func calculateRemainingTime(battery: BatteryState, averagePowerW: Double) -> TimeInterval?
}
