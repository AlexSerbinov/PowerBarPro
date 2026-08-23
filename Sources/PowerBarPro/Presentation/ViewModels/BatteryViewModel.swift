import Foundation
import Combine

/// Presentation logic for the battery display.
/// Provides both formatted text (for NSMenu) and structured fields (for SwiftUI popover).
final class BatteryViewModel: ObservableObject {

    // MARK: - Output (text for NSMenu)

    @Published private(set) var batteryText: String = "Battery: Calculating..."
    @Published private(set) var isVisible: Bool = true

    // MARK: - Output (structured for popover)

    @Published private(set) var percent: Double = 0
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isOnBattery: Bool = false
    @Published private(set) var timeRemainingText: String = ""
    @Published private(set) var energyWhText: String = ""
    @Published private(set) var healthPercent: Double = 0
    @Published private(set) var cycleCount: Int = 0
    @Published private(set) var temperatureC: Double = 0

    // MARK: - Dependencies

    private let batteryMonitor: BatteryMonitoring
    private let aggregator: PowerAggregating
    private let settings: SettingsStorage

    // MARK: - Init

    init(
        batteryMonitor: BatteryMonitoring,
        aggregator: PowerAggregating,
        settings: SettingsStorage
    ) {
        self.batteryMonitor = batteryMonitor
        self.aggregator = aggregator
        self.settings = settings
    }

    // MARK: - Public

    /// Recalculate battery display. Call whenever power metrics update.
    func refresh(currentMetrics: SystemMetrics?) {
        // Update structured fields from macpow battery data
        if let bat = currentMetrics?.battery {
            percent = bat.percent
            isCharging = bat.charging
            isOnBattery = !bat.externalConnected
            healthPercent = bat.healthPct ?? 0
            cycleCount = bat.cycleCount ?? 0
            temperatureC = bat.temperatureC ?? 0
            if let wh = bat.capacityWh {
                energyWhText = String(format: "%.1fWh", wh)
            }
        }

        // Fallback to ioreg battery data
        guard let batteryState = batteryMonitor.getBatteryState() else {
            batteryText = "Battery: Unavailable"
            isVisible = true
            return
        }

        isVisible = true

        let mode = settings.batteryDisplayMode
        guard let powerW = aggregator.resolvedPower(for: mode, instant: currentMetrics) else {
            batteryText = "Battery: Calculating..."
            return
        }

        let remainingWh = Formatters.power(batteryState.remainingEnergyWh)
            .replacingOccurrences(of: "W", with: "Wh")

        if let time = batteryMonitor.calculateRemainingTime(
            battery: batteryState,
            averagePowerW: powerW
        ) {
            let formatted = Formatters.remainingTime(time)
            timeRemainingText = formatted
            if batteryState.isOnBatteryPower {
                batteryText = "Battery: \(formatted) remaining - \(remainingWh)"
            } else {
                batteryText = "Battery: \(formatted) remaining (charging) - \(remainingWh)"
            }
        } else {
            timeRemainingText = ""
            if batteryState.isOnBatteryPower {
                batteryText = "Battery: \(remainingWh) remaining"
            } else {
                batteryText = "Battery: \(remainingWh) remaining (charging)"
            }
        }
    }
}
