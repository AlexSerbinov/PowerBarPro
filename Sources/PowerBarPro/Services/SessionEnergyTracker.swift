import Foundation

/// Integrates instantaneous power samples into total energy consumed
/// during this app session. Pure logic — no I/O, fully testable.
final class SessionEnergyTracker {

    /// Gaps longer than this are treated as sleep/wake — not integrated.
    private let maxGapSeconds: TimeInterval

    private(set) var energyWh: Double = 0
    let startedAt: Date
    private var lastTimestamp: Date?

    init(startedAt: Date = Date(), maxGapSeconds: TimeInterval = 30) {
        self.startedAt = startedAt
        self.maxGapSeconds = maxGapSeconds
    }

    /// Record a power sample. Energy is accumulated as watts × dt since
    /// the previous sample (trapezoid not needed at 1s cadence).
    func record(watts: Double, at date: Date = Date()) {
        defer { lastTimestamp = date }
        guard let last = lastTimestamp else { return }
        let dt = date.timeIntervalSince(last)
        guard dt > 0, dt <= maxGapSeconds else { return }
        energyWh += watts * dt / 3600
    }

    /// Average power over the active (integrated) session time.
    var sessionDuration: TimeInterval {
        max(0, (lastTimestamp ?? startedAt).timeIntervalSince(startedAt))
    }

    func reset(at date: Date = Date()) {
        energyWh = 0
        lastTimestamp = date
    }
}
