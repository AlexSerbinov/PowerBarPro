import Foundation
import Combine

/// Presentation logic for the menu bar power display.
/// Subscribes to power data and settings, emits formatted strings for the UI.
final class PowerDisplayViewModel: ObservableObject {

    // MARK: - Output (for UI binding)

    @Published private(set) var statusText: String = "Loading..."
    @Published private(set) var tooltipText: String = "PowerBar - macOS Power Monitor"
    @Published private(set) var detailsText: String = "Power Details"
    @Published private(set) var isError: Bool = false

    /// "0.82Wh · avg 11.2W · 42m" — energy consumed this app session.
    @Published private(set) var sessionSummary: String = ""

    // MARK: - Dependencies

    private let powerMonitor: PowerMonitoring
    private let aggregator: PowerAggregating
    private let settings: SettingsStorage
    private let sessionTracker: SessionEnergyTracker
    private var cancellables = Set<AnyCancellable>()

    // MARK: - State

    /// Exposed for consumers that need raw metrics (e.g. BatteryViewModel).
    @Published private(set) var currentMetrics: SystemMetrics?
    private var isRunning = false
    private var error: AppError?

    // MARK: - Init

    init(
        powerMonitor: PowerMonitoring,
        aggregator: PowerAggregating,
        settings: SettingsStorage,
        sessionTracker: SessionEnergyTracker = SessionEnergyTracker()
    ) {
        self.powerMonitor = powerMonitor
        self.aggregator = aggregator
        self.settings = settings
        self.sessionTracker = sessionTracker

        bindPowerMonitor()
        bindSettings()
    }

    // MARK: - Public

    /// Current resolved power value for external consumers (e.g. battery calc).
    func currentPowerValue() -> Double? {
        aggregator.resolvedPower(for: settings.displayMode, instant: currentMetrics)
    }

    /// Power value for a specific mode (e.g. battery's own mode).
    func powerValue(for mode: DisplayMode) -> Double? {
        aggregator.resolvedPower(for: mode, instant: currentMetrics)
    }

    /// Timestamped history readings for the given window (for the history chart).
    func historyReadings(seconds: Int) -> [PowerReading] {
        aggregator.readings(for: seconds)
    }

    // MARK: - Private

    private func bindPowerMonitor() {
        powerMonitor.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.currentMetrics = metrics
                if let m = metrics {
                    let reading = PowerReading(allPower: m.allPower, sysPower: m.sysPower)
                    self?.aggregator.record(reading)
                    self?.sessionTracker.record(watts: m.sysPower)
                    self?.updateSessionSummary()
                }
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        powerMonitor.isRunningPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.isRunning = running
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        powerMonitor.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        settings.displayModePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDisplay() }
            .store(in: &cancellables)

        settings.updateIntervalMsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                self?.powerMonitor.setUpdateInterval(interval)
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        if let error = error {
            statusText = "Error"
            tooltipText = error.localizedDescription
            detailsText = "Error: \(error.localizedDescription)"
            isError = true
            return
        }

        isError = false

        guard let metrics = currentMetrics else {
            statusText = isRunning ? "Loading..." : "Stopped"
            tooltipText = "PowerBar - macOS Power Monitor"
            detailsText = "Power Details"
            return
        }

        // Status text (menu bar title)
        let mode = settings.displayMode
        if let resolved = aggregator.resolvedPower(for: mode, instant: metrics) {
            statusText = Formatters.power(resolved)
        } else {
            statusText = Formatters.power(metrics.sysPower)
        }

        // Tooltip
        switch mode {
        case .instant:
            tooltipText = Formatters.detailedBreakdown(metrics)
        case .average(let seconds):
            if let avg = aggregator.average(for: seconds) {
                tooltipText = """
                Average (\(mode.displayName)):
                System: \(Formatters.power(avg.sysPower))
                Total: \(Formatters.power(avg.allPower))

                Current:
                \(Formatters.detailedBreakdown(metrics))
                """
            } else {
                tooltipText = "Average (\(mode.displayName)): Collecting data...\n\n"
                    + Formatters.detailedBreakdown(metrics)
            }
        }

        // Details menu item
        detailsText = Formatters.inlineBreakdown(metrics)
    }

    private func updateSessionSummary() {
        let wh = sessionTracker.energyWh
        let duration = sessionTracker.sessionDuration
        guard duration >= 5 else { return }

        let avgW = wh * 3600 / duration
        let durationText: String
        if duration >= 3600 {
            durationText = String(format: "%dh %02dm", Int(duration) / 3600, (Int(duration) % 3600) / 60)
        } else {
            durationText = "\(max(Int(duration) / 60, 1))m"
        }
        let whText = wh >= 10
            ? String(format: "%.1fWh", wh)
            : String(format: "%.2fWh", wh)
        sessionSummary = "\(whText) · avg \(String(format: "%.1f", avgW))W · \(durationText)"
    }
}
