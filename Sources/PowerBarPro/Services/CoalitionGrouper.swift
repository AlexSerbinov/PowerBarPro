import Foundation
import Darwin

/// Groups `ProcessPowerInfo` entries by app coalition (bundle name).
///
/// On macOS, coalition info is resolved by:
/// 1. Using `proc_pidpath` to get the full executable path, then extracting the
///    `.app` bundle name (e.g., `/Applications/Google Chrome.app/...` -> "Google Chrome").
/// 2. Stripping common helper suffixes from process names as fallback
///    (e.g., "Google Chrome Helper (Renderer)" -> "Google Chrome").
///
/// Results are sorted by `totalPowerWatts` descending.
final class CoalitionGrouper: CoalitionGrouping {

    // MARK: - Types

    /// Resolver function that returns the executable path for a PID.
    /// Injected for testability — production uses `proc_pidpath`, tests use a stub.
    typealias PathResolver = (pid_t) -> String?

    // MARK: - Constants

    /// Known helper suffixes stripped when resolving app names from process names.
    static let helperSuffixes: [String] = [
        " Helper (Renderer)",
        " Helper (GPU)",
        " Helper (Plugin)",
        " Helper (Utility)",
        " Helper",
        " Worker",
        " (Renderer)",
        " (GPU)",
        " (Plugin)",
        " Networking",
        " Web Content",
    ]

    // MARK: - State

    /// Cache of resolved PID -> app name to avoid repeated syscalls.
    /// Guarded by `cacheLock` — resolveAppName may be called from multiple queues.
    private var pidNameCache: [pid_t: String] = [:]
    private let cacheLock = NSLock()

    /// The path resolver function. Defaults to `proc_pidpath` via `getProcessPath`.
    private let pathResolver: PathResolver

    // MARK: - Init

    /// - Parameter pathResolver: Custom path resolver for testing.
    ///   Defaults to the real `proc_pidpath` implementation.
    init(pathResolver: PathResolver? = nil) {
        self.pathResolver = pathResolver ?? CoalitionGrouper.defaultPathResolver
    }

    // MARK: - Public API

    /// Group process power entries into coalitions (app bundles).
    ///
    /// - Parameters:
    ///   - processes: Per-process power info from `ProcessEnergyService`.
    ///   - systemPowerW: Total system power in watts, used to compute percentages.
    /// - Returns: Array of `CoalitionInfo` sorted by power descending.
    func group(_ processes: [ProcessPowerInfo], systemPowerW: Double) -> [CoalitionInfo] {
        guard !processes.isEmpty else { return [] }

        // Accumulator per coalition name
        struct Accumulator {
            var pids: [pid_t] = []
            var totalPowerWatts: Double = 0
            var totalMemoryBytes: UInt64 = 0
            var processCount: Int = 0
        }

        var coalitions: [String: Accumulator] = [:]

        for process in processes {
            let coalitionName = resolveCoalitionName(for: process)

            var acc = coalitions[coalitionName] ?? Accumulator()
            acc.pids.append(contentsOf: process.pids)
            acc.totalPowerWatts += process.powerWatts
            acc.totalMemoryBytes += process.memoryBytes
            acc.processCount += 1
            coalitions[coalitionName] = acc
        }

        let effectiveSystemPower = max(systemPowerW, 0.001)

        var results: [CoalitionInfo] = coalitions.map { name, acc in
            let percent = (acc.totalPowerWatts / effectiveSystemPower) * 100.0

            return CoalitionInfo(
                id: name,
                name: name,
                pids: acc.pids,
                totalPowerWatts: acc.totalPowerWatts,
                percentOfSystem: min(percent, 100.0),
                totalMemoryBytes: acc.totalMemoryBytes,
                processCount: acc.processCount
            )
        }

        results.sort { $0.totalPowerWatts > $1.totalPowerWatts }
        return results
    }

    /// Extract app bundle name from a PID's executable path.
    ///
    /// - Parameter pid: The process ID to resolve.
    /// - Returns: The `.app` bundle name if found, or `nil` for CLI tools.
    func resolveAppName(pid: pid_t) -> String? {
        cacheLock.lock()
        let cached = pidNameCache[pid]
        cacheLock.unlock()
        if let cached = cached {
            return cached
        }

        guard let path = pathResolver(pid) else { return nil }

        let name = extractAppBundleName(from: path)
        if let name = name {
            cacheLock.lock()
            pidNameCache[pid] = name
            cacheLock.unlock()
        }
        return name
    }

    /// Clear the PID -> app name cache.
    /// Call when process list changes significantly (e.g., after a refresh cycle).
    func clearCache() {
        cacheLock.lock()
        pidNameCache.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Private

    /// Resolve the coalition name for a process.
    /// Tries PID path resolution first, then falls back to name-based suffix stripping.
    private func resolveCoalitionName(for process: ProcessPowerInfo) -> String {
        // Try resolving via the first PID's executable path
        if let firstPid = process.pids.first,
           let appName = resolveAppName(pid: firstPid) {
            return appName
        }

        // Fallback: strip helper suffixes from the process name
        return stripHelperSuffixes(from: process.name)
    }

    /// Extract the `.app` bundle name from a full executable path.
    ///
    /// Examples:
    /// - `/Applications/Google Chrome.app/Contents/Frameworks/.../Helper` -> "Google Chrome"
    /// - `/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal` -> "Terminal"
    /// - `/usr/bin/python3` -> nil (not an app bundle)
    func extractAppBundleName(from path: String) -> String? {
        // Scan for ".app/" or ".app" at end of a path component
        guard let appRange = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards) else {
            return nil
        }

        // Get everything before ".app"
        let beforeApp = path[path.startIndex..<appRange.lowerBound]

        // Find the last "/" before ".app" to isolate the bundle name
        if let lastSlash = beforeApp.lastIndex(of: "/") {
            let bundleName = String(beforeApp[beforeApp.index(after: lastSlash)...])
            return bundleName.isEmpty ? nil : bundleName
        }

        // No slash found — the path starts with the bundle name
        let bundleName = String(beforeApp)
        return bundleName.isEmpty ? nil : bundleName
    }

    /// Strip known helper suffixes from a process name.
    ///
    /// Examples:
    /// - "Google Chrome Helper (Renderer)" -> "Google Chrome"
    /// - "Slack Helper" -> "Slack"
    /// - "python3" -> "python3" (no suffix to strip)
    func stripHelperSuffixes(from name: String) -> String {
        for suffix in Self.helperSuffixes {
            if name.hasSuffix(suffix) {
                let stripped = String(name.dropLast(suffix.count))
                return stripped.isEmpty ? name : stripped
            }
        }
        return name
    }

    // MARK: - Default Path Resolver

    /// Production path resolver using `proc_pidpath`.
    private static func defaultPathResolver(pid: pid_t) -> String? {
        let bufferSize = Int(MAXPATHLEN)
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { pathBuffer.deallocate() }
        let result = proc_pidpath(pid, pathBuffer, UInt32(bufferSize))
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }
}
