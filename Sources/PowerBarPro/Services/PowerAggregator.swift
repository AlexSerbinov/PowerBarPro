import Foundation

/// Maintains a rolling buffer of power readings and calculates
/// time-based averages. Pure logic — no I/O, fully testable.
final class PowerAggregator {

    private var history: [PowerReading] = []
    private let maxHistoryDuration: TimeInterval

    init(maxHistoryDuration: TimeInterval = Constants.Defaults.maxHistoryDuration) {
        self.maxHistoryDuration = maxHistoryDuration
    }

    // MARK: - Public API

    /// Record a new power sample.
    func record(_ reading: PowerReading) {
        history.append(reading)
        pruneOldReadings()
    }

    /// Remove all recorded readings.
    func reset() {
        history.removeAll()
    }

    /// Get readings within a time window.
    /// - Parameter seconds: Window size. 0 = all history.
    func readings(for seconds: Int) -> [PowerReading] {
        if seconds == 0 {
            return history
        }
        let cutoff = Date().addingTimeInterval(-TimeInterval(seconds))
        return history.filter { $0.timestamp >= cutoff }
    }

    /// Calculate average power for a time window.
    /// Returns `nil` if no readings are available for the period.
    func average(for seconds: Int) -> (allPower: Double, sysPower: Double)? {
        let relevant = readings(for: seconds)
        guard !relevant.isEmpty else { return nil }

        let avgAll = relevant.map(\.allPower).reduce(0, +) / Double(relevant.count)
        let avgSys = relevant.map(\.sysPower).reduce(0, +) / Double(relevant.count)
        return (allPower: avgAll, sysPower: avgSys)
    }

    /// Resolve the effective power value for a given display mode.
    /// Falls back to instant if averaging data is insufficient.
    func resolvedPower(for mode: DisplayMode, instant: PowerMetrics?) -> Double? {
        guard let metrics = instant else { return nil }

        switch mode {
        case .instant:
            return metrics.sysPower
        case .average(let seconds):
            if let avg = average(for: seconds) {
                return avg.sysPower
            }
            return metrics.sysPower  // Fallback to instant
        }
    }

    /// Number of readings currently in the buffer.
    var readingCount: Int { history.count }

    // MARK: - Private

    private func pruneOldReadings() {
        let cutoff = Date().addingTimeInterval(-maxHistoryDuration)
        history.removeAll { $0.timestamp < cutoff }
    }
}
