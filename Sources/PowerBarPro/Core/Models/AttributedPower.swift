import Foundation

/// Per-process power breakdown with attributed component contributions.
/// This is the output of PowerAttributionEngine — much more accurate
/// than raw proc_pid_rusage which only captures CPU instruction energy.
struct AttributedPower: Identifiable, Equatable {
    let id: String              // process name (grouped)
    let name: String
    let pids: [pid_t]

    // Attributed component breakdown
    let cpuWatts: Double        // CPU energy share
    let dramWatts: Double       // DRAM share (proportional to RSS)
    let gpuWatts: Double        // GPU share (proportional to GPU time)
    let storageWatts: Double    // Storage share (proportional to disk I/O)

    // Totals
    var totalWatts: Double {
        cpuWatts + dramWatts + gpuWatts + storageWatts
    }

    let percentOfSystem: Double // % of sys_power_w
    let memoryBytes: UInt64
    let pidCount: Int

    // Raw (uncorrected) value for comparison/calibration
    let rawCpuWatts: Double
}

/// Component power budget from IOReport/macpow — the "truth" we distribute.
struct ComponentPowerBudget: Equatable {
    let cpuW: Double
    let dramW: Double
    let gpuW: Double
    let storageW: Double
    let fabricW: Double    // distributed proportionally to CPU
    let systemTotalW: Double

    /// Create from SystemMetrics (macpow data).
    static func from(_ metrics: SystemMetrics) -> ComponentPowerBudget {
        ComponentPowerBudget(
            cpuW: metrics.soc.cpuW,
            dramW: metrics.soc.dramW,
            gpuW: metrics.soc.gpuW,
            storageW: metrics.ssdPowerW,
            fabricW: metrics.soc.fabricW,
            systemTotalW: metrics.sysPowerW
        )
    }
}

/// Raw per-process usage data needed for proportional attribution.
struct ProcessUsageData {
    let name: String
    let pids: [pid_t]
    let cpuEnergyNJ: Double     // from proc_pid_rusage ri_energy_nj (delta)
    let memoryBytes: UInt64     // RSS
    let gpuTimeNS: Double       // GPU time (if available, 0 otherwise)
    let diskIOBytes: Double     // total disk I/O bytes (delta)
}
