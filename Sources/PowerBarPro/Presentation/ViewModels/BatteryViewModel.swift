import Foundation
import Combine

/// Presentation logic for the battery time remaining display.
final class BatteryViewModel: ObservableObject {

    // MARK: - Output

    @Published private(set) var batteryText: String = "Battery: Calculating..."
    @Published private(set) var isVisible: Bool = true

    // MARK: - Dependencies

    private let batteryMonitor: BatteryMonitoring
    private let aggregator: PowerAggregator
    private let settings: SettingsStorage

    // MARK: - Init

    init(
        batteryMonitor: BatteryMonitoring,
        aggregator: PowerAggregator,
        settings: SettingsStorage
    ) {
        self.batteryMonitor = batteryMonitor
        self.aggregator = aggregator
        self.settings = settings
    }

    // MARK: - Public

    /// Recalculate battery display. Call whenever power metrics update.
    func refresh(currentMetrics: PowerMetrics?) {
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
            if batteryState.isOnBatteryPower {
                batteryText = "Battery: \(formatted) remaining - \(remainingWh)"
            } else {
                batteryText = "Battery: \(formatted) remaining (charging) - \(remainingWh)"
            }
        } else {
            if batteryState.isOnBatteryPower {
                batteryText = "Battery: \(remainingWh) remaining"
            } else {
                batteryText = "Battery: \(remainingWh) remaining (charging)"
            }
        }
    }
}
