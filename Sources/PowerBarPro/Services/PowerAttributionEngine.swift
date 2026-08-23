import Foundation

/// Distributes known component-level power (from IOReport/macpow) across processes
/// proportionally to each process's usage of that component.
///
/// This is the Kepler-style approach: we know EXACT power per component (CPU, DRAM, GPU, SSD)
/// from hardware counters. We distribute each component's power to processes proportional
/// to their share of that component's usage.
///
/// Result: sum of all processes' attributed power ≈ total SoC power.
/// Much more accurate than raw proc_pid_rusage (which only captures CPU instruction energy).
final class PowerAttributionEngine: PowerAttributing {

    // MARK: - Calibration coefficient (from CalibrationService)

    private let lock = NSLock()
    private var _globalCoefficient: Double = 1.0
    private var _appCoefficients: [String: Double] = [:]

    /// Global correction multiplier applied after proportional attribution.
    var globalCoefficient: Double {
        get { lock.lock(); defer { lock.unlock() }; return _globalCoefficient }
        set { lock.lock(); defer { lock.unlock() }; _globalCoefficient = newValue }
    }

    /// Per-app coefficients (app name → multiplier). Takes priority over global.
    var appCoefficients: [String: Double] {
        get { lock.lock(); defer { lock.unlock() }; return _appCoefficients }
        set { lock.lock(); defer { lock.unlock() }; _appCoefficients = newValue }
    }

    // MARK: - Core Attribution

    /// Distribute component power across processes using proportional attribution.
    ///
    /// - Parameters:
    ///   - processes: Raw usage data per process (from ProcessEnergyService)
    ///   - budget: Known component power from IOReport/macpow
    /// - Returns: Attributed power per process, sorted by totalWatts descending
    func attribute(
        processes: [ProcessUsageData],
        budget: ComponentPowerBudget
    ) -> [AttributedPower] {
        guard !processes.isEmpty else { return [] }

        // Calculate totals for each component across all processes
        let totalCpuEnergy = processes.map(\.cpuEnergyNJ).reduce(0, +)
        let totalMemory = processes.map { Double($0.memoryBytes) }.reduce(0, +)
        let totalGpuTime = processes.map(\.gpuTimeNS).reduce(0, +)
        let totalDiskIO = processes.map(\.diskIOBytes).reduce(0, +)

        // Available power per component (CPU gets fabric bonus — fabric serves CPU mostly)
        let cpuBudget = budget.cpuW + budget.fabricW * 0.7  // 70% of fabric → CPU
        let dramBudget = budget.dramW + budget.fabricW * 0.2  // 20% → DRAM access
        let gpuBudget = budget.gpuW + budget.fabricW * 0.1   // 10% → GPU
        let storageBudget = budget.storageW

        let results = processes.map { proc -> AttributedPower in
            // Proportional share of each component
            let cpuShare = totalCpuEnergy > 0
                ? (proc.cpuEnergyNJ / totalCpuEnergy)
                : 0

            let dramShare = totalMemory > 0
                ? (Double(proc.memoryBytes) / totalMemory)
                : 0

            let gpuShare = totalGpuTime > 0
                ? (proc.gpuTimeNS / totalGpuTime)
                : 0

            let diskShare = totalDiskIO > 0
                ? (proc.diskIOBytes / totalDiskIO)
                : 0

            // Attributed watts per component
            var cpuW = cpuShare * cpuBudget
            var dramW = dramShare * dramBudget
            var gpuW = gpuShare * gpuBudget
            var storageW = diskShare * storageBudget

            // Apply calibration coefficient
            let coeff = appCoefficients[proc.name] ?? globalCoefficient
            cpuW *= coeff
            dramW *= coeff
            gpuW *= coeff
            storageW *= coeff

            let total = cpuW + dramW + gpuW + storageW
            let pctOfSystem = budget.systemTotalW > 0
                ? (total / budget.systemTotalW) * 100
                : 0

            // Raw CPU-only watts (what proc_pid_rusage would show)
            let rawCpuW = totalCpuEnergy > 0
                ? cpuShare * budget.cpuW
                : 0

            return AttributedPower(
                id: proc.name,
                name: proc.name,
                pids: proc.pids,
                cpuWatts: cpuW,
                dramWatts: dramW,
                gpuWatts: gpuW,
                storageWatts: storageW,
                percentOfSystem: pctOfSystem,
                memoryBytes: proc.memoryBytes,
                pidCount: proc.pids.count,
                rawCpuWatts: rawCpuW
            )
        }

        return results.sorted { $0.totalWatts > $1.totalWatts }
    }

    // MARK: - Convenience

    /// Quick attribution from SystemMetrics + ProcessPowerInfo (current pipeline).
    func attribute(
        processInfos: [ProcessPowerInfo],
        metrics: SystemMetrics
    ) -> [AttributedPower] {
        let budget = ComponentPowerBudget.from(metrics)

        let usageData = processInfos.map { proc in
            ProcessUsageData(
                name: proc.name,
                pids: proc.pids,
                cpuEnergyNJ: proc.powerWatts * 1e9, // Convert back to energy-like unit for ratio
                memoryBytes: proc.memoryBytes,
                gpuTimeNS: 0,       // Not available from proc_pid_rusage
                diskIOBytes: 0      // Not available in current pipeline
            )
        }

        return attribute(processes: usageData, budget: budget)
    }

    /// Calculate the "correction factor" — how much bigger attributed values are vs raw.
    /// Useful for displaying to users during calibration.
    func averageCorrectionFactor(
        attributed: [AttributedPower]
    ) -> Double {
        let pairs = attributed.filter { $0.rawCpuWatts > 0.001 }
        guard !pairs.isEmpty else { return 1.0 }

        let ratios = pairs.map { $0.totalWatts / $0.rawCpuWatts }
        return ratios.reduce(0, +) / Double(ratios.count)
    }
}
