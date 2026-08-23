import Foundation

/// Represents a coalition (app bundle) with aggregated power data.
///
/// macOS XNU groups processes into "coalitions" — all processes of one app
/// share a coalition (e.g., all Chrome helper processes = one "Google Chrome"
/// coalition). This struct holds the aggregated metrics for one such group.
struct CoalitionInfo: Identifiable, Equatable {
    let id: String                // coalition name (bundle name)
    let name: String              // display name
    let pids: [pid_t]             // all PIDs in this coalition
    let totalPowerWatts: Double   // sum of all PIDs' attributed power
    let percentOfSystem: Double   // % of total system power
    let totalMemoryBytes: UInt64  // sum of all PIDs' memory
    let processCount: Int         // number of processes
}
