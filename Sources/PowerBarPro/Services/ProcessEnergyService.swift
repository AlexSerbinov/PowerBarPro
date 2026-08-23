import Foundation
import Darwin

// MARK: - Data Models

/// A point-in-time energy snapshot for a single process.
struct ProcessEnergySnapshot {
    let pid: pid_t
    let name: String
    let energyNJ: UInt64
    let timestamp: Date
}

/// Aggregated power information for a process (or group of PIDs sharing a name).
struct ProcessPowerInfo: Identifiable {
    let id: String        // process name (used as grouping key)
    let name: String
    let powerWatts: Double
    let percentOfSystem: Double
    let memoryBytes: UInt64
    let pidCount: Int     // how many PIDs share this name
    let pids: [pid_t]
}

// MARK: - Service

/// Measures per-process energy consumption using `proc_pid_rusage` and
/// calculates instantaneous power by tracking energy deltas between samples.
///
/// Energy values come from the `ri_energy_nj` field of `rusage_info_v6`,
/// which reports cumulative nanojoules consumed by the process since launch.
/// Power in watts is derived as:
///
///     W = (energy_t2 - energy_t1) / dt / 1_000_000_000
///
/// Results are grouped by process name (multiple PIDs with the same name
/// are aggregated) and smoothed with an exponential moving average.
final class ProcessEnergyService: ProcessMonitoring {

    // MARK: - Constants

    /// `RUSAGE_INFO_V6` flavor constant for `proc_pid_rusage`.
    private static let rusageInfoV6: Int32 = 6

    /// Byte offset of `ri_energy_nj` within the `rusage_info_v6` struct.
    /// Layout: 16 bytes UUID + 40 * 8 bytes of uint64 fields = offset 336.
    private static let energyNJOffset = 16 + 40 * 8  // 336

    /// Size of the raw buffer used to receive rusage data.
    private static let rusageBufferSize = 1024

    /// EMA smoothing factor. Higher values react faster to changes.
    private let emaSmoothingFactor: Double

    // MARK: - State

    /// Previous energy snapshot per PID, keyed by pid_t.
    private var previousSnapshots: [pid_t: ProcessEnergySnapshot] = [:]

    /// EMA-smoothed power per process name.
    private var smoothedPower: [String: Double] = [:]

    // MARK: - Init

    /// - Parameter emaSmoothingFactor: Smoothing factor in range (0, 1].
    ///   Default is 0.3 (moderate smoothing).
    init(emaSmoothingFactor: Double = 0.3) {
        self.emaSmoothingFactor = max(0.01, min(1.0, emaSmoothingFactor))
    }

    // MARK: - ProcessMonitoring

    func sampleProcesses(systemPowerW: Double) -> [ProcessPowerInfo] {
        let now = Date()
        let pids = listAllPids()
        var currentSnapshots: [pid_t: ProcessEnergySnapshot] = [:]

        // Intermediate: raw power per PID before grouping
        struct PidPower {
            let pid: pid_t
            let name: String
            let watts: Double
            let memoryBytes: UInt64
        }

        var pidPowers: [PidPower] = []

        for pid in pids {
            guard let energyNJ = getProcessEnergyNJ(pid: pid) else { continue }

            let name = resolveProcessName(pid: pid)
            let snapshot = ProcessEnergySnapshot(
                pid: pid,
                name: name,
                energyNJ: energyNJ,
                timestamp: now
            )
            currentSnapshots[pid] = snapshot

            // Calculate delta if we have a previous reading
            if let prev = previousSnapshots[pid], prev.name == name {
                let dt = now.timeIntervalSince(prev.timestamp)
                guard dt > 0.01 else { continue }  // avoid division by near-zero

                let deltaEnergy = energyNJ >= prev.energyNJ
                    ? energyNJ - prev.energyNJ
                    : energyNJ  // counter wrapped or process restarted

                let watts = Double(deltaEnergy) / dt / 1_000_000_000.0

                // Skip unreasonably large values (likely counter reset)
                guard watts < 500.0 else { continue }

                let memBytes = getProcessMemoryBytes(pid: pid)

                pidPowers.append(PidPower(
                    pid: pid,
                    name: name,
                    watts: watts,
                    memoryBytes: memBytes
                ))
            }
        }

        // Replace previous snapshots with current
        previousSnapshots = currentSnapshots

        // Group by process name
        var grouped: [String: (watts: Double, memory: UInt64, pids: [pid_t])] = [:]
        for pp in pidPowers {
            var entry = grouped[pp.name] ?? (watts: 0, memory: 0, pids: [])
            entry.watts += pp.watts
            entry.memory += pp.memoryBytes
            entry.pids.append(pp.pid)
            grouped[pp.name] = entry
        }

        // Apply EMA smoothing per process name
        for (name, info) in grouped {
            if let prev = smoothedPower[name] {
                smoothedPower[name] = emaSmoothingFactor * info.watts
                    + (1.0 - emaSmoothingFactor) * prev
            } else {
                smoothedPower[name] = info.watts
            }
        }

        // Decay processes that disappeared from this sample
        let currentNames = Set(grouped.keys)
        for name in smoothedPower.keys where !currentNames.contains(name) {
            smoothedPower[name] = (smoothedPower[name] ?? 0) * (1.0 - emaSmoothingFactor)
            if (smoothedPower[name] ?? 0) < 0.001 {
                smoothedPower.removeValue(forKey: name)
            }
        }

        // Build results
        let effectiveSystemPower = max(systemPowerW, 0.001)
        var results: [ProcessPowerInfo] = []

        for (name, info) in grouped {
            let smoothed = smoothedPower[name] ?? info.watts
            let percent = (smoothed / effectiveSystemPower) * 100.0

            results.append(ProcessPowerInfo(
                id: name,
                name: name,
                powerWatts: smoothed,
                percentOfSystem: min(percent, 100.0),
                memoryBytes: info.memory,
                pidCount: info.pids.count,
                pids: info.pids
            ))
        }

        // Sort by power descending
        results.sort { $0.powerWatts > $1.powerWatts }
        return results
    }

    func reset() {
        previousSnapshots.removeAll()
        smoothedPower.removeAll()
    }

    // MARK: - Private: proc_pid_rusage

    /// Read the cumulative energy in nanojoules for a process.
    /// Uses `proc_pid_rusage` with `RUSAGE_INFO_V6` flavor.
    private func getProcessEnergyNJ(pid: pid_t) -> UInt64? {
        var buffer = [UInt8](repeating: 0, count: Self.rusageBufferSize)
        let result = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            // proc_pid_rusage expects a pointer to a rusage_info_t (opaque pointer).
            // We pass a raw byte buffer and reinterpret.
            ptr.baseAddress!.withMemoryRebound(
                to: Optional<rusage_info_t>.self,
                capacity: 1
            ) { rusagePtr in
                proc_pid_rusage(pid, Self.rusageInfoV6, rusagePtr)
            }
        }
        guard result == 0 else { return nil }

        // Read ri_energy_nj at the known offset within the struct
        return buffer.withUnsafeBufferPointer { ptr in
            guard Self.energyNJOffset + MemoryLayout<UInt64>.size <= ptr.count else {
                return nil
            }
            return ptr.baseAddress!.advanced(by: Self.energyNJOffset)
                .withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
        }
    }

    /// Resident memory (bytes) for a process via `proc_pid_rusage`.
    /// `ri_phys_footprint` is at offset 16 + 34*8 = 288 in rusage_info_v4+.
    private func getProcessMemoryBytes(pid: pid_t) -> UInt64 {
        var buffer = [UInt8](repeating: 0, count: Self.rusageBufferSize)
        let result = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            ptr.baseAddress!.withMemoryRebound(
                to: Optional<rusage_info_t>.self,
                capacity: 1
            ) { rusagePtr in
                proc_pid_rusage(pid, Self.rusageInfoV6, rusagePtr)
            }
        }
        guard result == 0 else { return 0 }

        let physFootprintOffset = 16 + 34 * 8  // 288
        return buffer.withUnsafeBufferPointer { ptr in
            guard physFootprintOffset + MemoryLayout<UInt64>.size <= ptr.count else {
                return 0
            }
            return ptr.baseAddress!.advanced(by: physFootprintOffset)
                .withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
        }
    }

    // MARK: - Private: Process enumeration

    /// List all PIDs currently running on the system.
    private func listAllPids() -> [pid_t] {
        // First call: get the required buffer size
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        // Allocate buffer with some headroom for new processes
        let bufferSize = Int(count) + 64
        var pids = [pid_t](repeating: 0, count: bufferSize)
        let actualCount = pids.withUnsafeMutableBufferPointer { ptr in
            proc_listallpids(ptr.baseAddress, Int32(bufferSize * MemoryLayout<pid_t>.size))
        }
        guard actualCount > 0 else { return [] }

        return Array(pids.prefix(Int(actualCount)))
    }

    /// Resolve a process name from its PID.
    /// Tries `proc_name` first; falls back to "pid:\(pid)".
    private func resolveProcessName(pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if length > 0, let name = String(cString: nameBuffer, encoding: .utf8), !name.isEmpty {
            return name
        }

        // Fallback: try proc_pidpath for the executable basename
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLength > 0 {
            let fullPath = String(cString: pathBuffer)
            if let lastComponent = fullPath.split(separator: "/").last {
                return String(lastComponent)
            }
        }

        return "pid:\(pid)"
    }
}
