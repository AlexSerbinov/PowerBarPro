import Foundation

/// Composition root — creates and wires all dependencies.
/// Every service is created once and shared through protocol references.
///
/// Extension points for future features:
/// - Add `ProcessListService` for active process monitoring
/// - Add `ScreenPowerService` for display wattage tracking
/// - Add `PerCoreMetricsService` for per-core energy breakdown
final class DependencyContainer {

    // MARK: - Services

    let settings: SettingsStorage
    let processRunner: ProcessRunning
    let powerMonitor: PowerMonitoring
    let batteryMonitor: BatteryMonitoring
    let powerAggregator: PowerAggregator

    // MARK: - ViewModels

    let powerDisplayVM: PowerDisplayViewModel
    let batteryVM: BatteryViewModel

    // MARK: - Presentation

    let menuBarManager: MenuBarManager

    // MARK: - Init

    init() {
        // Layer 1: Infrastructure
        settings = UserDefaultsStore()
        processRunner = ProcessRunner()

        // Layer 2: Data services
        let macMonService = MacMonService(processRunner: processRunner)
        powerMonitor = macMonService

        let batteryService = SystemBatteryService(processRunner: processRunner)
        batteryMonitor = batteryService

        powerAggregator = PowerAggregator(
            maxHistoryDuration: Constants.Defaults.maxHistoryDuration
        )

        // Layer 3: ViewModels
        powerDisplayVM = PowerDisplayViewModel(
            powerMonitor: macMonService,
            aggregator: powerAggregator,
            settings: settings
        )

        batteryVM = BatteryViewModel(
            batteryMonitor: batteryService,
            aggregator: powerAggregator,
            settings: settings
        )

        // Layer 4: Presentation
        menuBarManager = MenuBarManager(
            powerDisplayVM: powerDisplayVM,
            batteryVM: batteryVM,
            settings: settings
        )
    }
}
