import Foundation
import Combine

/// Abstraction over power data collection (macpow/macmon subprocess).
/// Implementations: `MacPowService` (production), `MockPowerMonitor` (tests).
protocol PowerMonitoring: AnyObject {
    /// Latest metrics from the power data source. `nil` until first reading.
    var metricsPublisher: AnyPublisher<SystemMetrics?, Never> { get }

    /// Current error state. `nil` when healthy.
    var errorPublisher: AnyPublisher<AppError?, Never> { get }

    /// Whether the monitoring subprocess is actively running.
    var isRunningPublisher: AnyPublisher<Bool, Never> { get }

    /// Start collecting power metrics. No-op if already running.
    func startMonitoring()

    /// Stop collecting and release resources.
    func stopMonitoring()

    /// Restart monitoring with a new sample interval.
    func setUpdateInterval(_ intervalMs: Int)
}
