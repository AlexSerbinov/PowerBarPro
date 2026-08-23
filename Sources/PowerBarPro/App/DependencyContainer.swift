import Foundation

/// Composition root — creates and wires all dependencies.
/// Every service is created once and shared through protocol references.
final class DependencyContainer {

    // MARK: - Services

    let settings: SettingsStorage
    let processRunner: ProcessRunning
    let powerMonitor: PowerMonitoring
    let batteryMonitor: BatteryMonitoring
    let powerAggregator: PowerAggregating
    let processEnergyService: ProcessMonitoring
    let processTerminator: ProcessTerminating
    let attributionEngine: PowerAttributing
    let calibrationService: CalibrationService
    let coalitionGrouper: CoalitionGrouping
    let processDescriptionService: ProcessDescriptionService

    // MARK: - ViewModels

    let powerDisplayVM: PowerDisplayViewModel
    let batteryVM: BatteryViewModel
    let processListVM: ProcessListViewModel

    // MARK: - Presentation

    let menuBarManager: MenuBarManager

    // MARK: - Init

    init() {
        // Layer 1: Infrastructure
        settings = UserDefaultsStore()
        processRunner = ProcessRunner()

        // Layer 2: Data services
        let macPowService = MacPowService(processRunner: processRunner)
        powerMonitor = macPowService

        let batteryService = SystemBatteryService(processRunner: processRunner)
        batteryMonitor = batteryService

        powerAggregator = PowerAggregator(
            maxHistoryDuration: Constants.Defaults.maxHistoryDuration
        )

        processEnergyService = ProcessEnergyService()
        processTerminator = ProcessTerminator()
        coalitionGrouper = CoalitionGrouper()

        // Layer 2.5: Attribution & Calibration
        let engine = PowerAttributionEngine()
        attributionEngine = engine

        let calibration = CalibrationService(processTerminator: processTerminator)
        calibrationService = calibration

        // Wire calibration coefficients → attribution engine
        for (name, result) in calibration.store.appCoefficients where result.isReliable {
            engine.appCoefficients[name] = result.coefficient
        }
        engine.globalCoefficient = calibration.store.globalCoefficient

        processDescriptionService = ProcessDescriptionService()

        // Layer 3: ViewModels
        powerDisplayVM = PowerDisplayViewModel(
            powerMonitor: macPowService,
            aggregator: powerAggregator,
            settings: settings
        )

        batteryVM = BatteryViewModel(
            batteryMonitor: batteryService,
            aggregator: powerAggregator,
            settings: settings
        )

        processListVM = ProcessListViewModel(
            processMonitor: processEnergyService,
            terminator: processTerminator,
            attributionEngine: engine,
            coalitionGrouper: coalitionGrouper
        )

        // Layer 4: Presentation
        menuBarManager = MenuBarManager(
            powerDisplayVM: powerDisplayVM,
            batteryVM: batteryVM,
            processListVM: processListVM,
            settings: settings,
            processDescriptionService: processDescriptionService
        )
    }
}
