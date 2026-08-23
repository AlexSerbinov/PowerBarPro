import Foundation

/// Abstraction over per-process energy sampling.
/// Implementations: `ProcessEnergyService` (production).
protocol ProcessMonitoring {
    /// Sample all running processes and return power info sorted by watts descending.
    /// - Parameter systemPowerW: Current total system power in watts, used to
    ///   compute each process's percentage contribution.
    func sampleProcesses(systemPowerW: Double) -> [ProcessPowerInfo]

    /// Clear accumulated snapshots and EMA state.
    func reset()
}
