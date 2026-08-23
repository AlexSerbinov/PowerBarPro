import Foundation
import Combine

/// Presentation logic for the per-app energy consumption list.
/// Pipeline: ProcessEnergyService → PowerAttributionEngine → Averaging → CoalitionGrouper → UI
final class ProcessListViewModel: ObservableObject {

    // MARK: - Output

    @Published private(set) var attributedProcesses: [AttributedPower] = []
    @Published private(set) var coalitions: [CoalitionInfo] = []
    @Published private(set) var displayPowerText: String = ""
    @Published private(set) var displayPowerW: Double = 0
    @Published private(set) var correctionFactor: Double = 1.0

    // MARK: - Dependencies

    private let processMonitor: ProcessMonitoring
    private let terminator: ProcessTerminating
    private let attributionEngine: PowerAttributing
    private let coalitionGrouper: CoalitionGrouping

    // MARK: - Process Power History (for averaging)

    /// Rolling history: [processName: [(timestamp, watts)]]
    private var processHistory: [String: [(Date, Double)]] = [:]
    private let historyLock = NSLock()
    private let maxHistorySeconds: TimeInterval = 600 // Keep up to 10 min
    var averagingSeconds: Int = Constants.Defaults.processAveragingSeconds

    // MARK: - Init

    init(
        processMonitor: ProcessMonitoring,
        terminator: ProcessTerminating,
        attributionEngine: PowerAttributing = PowerAttributionEngine(),
        coalitionGrouper: CoalitionGrouping = CoalitionGrouper()
    ) {
        self.processMonitor = processMonitor
        self.terminator = terminator
        self.attributionEngine = attributionEngine
        self.coalitionGrouper = coalitionGrouper
    }

    private var refreshCount = 0

    // MARK: - Public

    /// Minimum interval between expensive process scans (seconds).
    /// Prevents proc_pid_rusage spam which causes high CPU/energy usage.
    private var lastProcessScan: Date = .distantPast

    /// True while any UI that shows the process list is on screen
    /// (popover or right-click menu). Off-screen we still scan — the
    /// power-hog alert service needs data — but 3x less often.
    var isUIVisible = false {
        didSet {
            // Refresh promptly when the user opens the UI after idle
            if isUIVisible && !oldValue { lastProcessScan = .distantPast }
        }
    }

    private let visibleScanInterval: TimeInterval = 5.0
    private let backgroundScanInterval: TimeInterval = 15.0
    private var minScanInterval: TimeInterval {
        isUIVisible ? visibleScanInterval : backgroundScanInterval
    }

    /// Update process list with current system metrics.
    /// Display power updates every call. Process scan throttled to minScanInterval.
    func refresh(metrics: SystemMetrics?) {
        guard let metrics = metrics else { return }

        // Periodically clear caches
        refreshCount += 1
        if refreshCount % 100 == 0 {
            coalitionGrouper.clearCache()
            pruneHistory()
        }

        // Display power (cheap — always update)
        let backlightW = metrics.backlightPowerW
        let displayEstW = metrics.display?.estimatedPowerW ?? 0
        let totalDisplayW = max(backlightW, displayEstW)
        displayPowerW = totalDisplayW

        if let display = metrics.display, display.available {
            displayPowerText = String(format: "Display: %.2fW (%.0f%% brightness)", totalDisplayW, display.brightnessPct)
        } else {
            displayPowerText = String(format: "Display: %.2fW", totalDisplayW)
        }

        // Throttle expensive process scanning (proc_pid_rusage for all PIDs)
        let now = Date()
        if now.timeIntervalSince(lastProcessScan) >= minScanInterval {
            lastProcessScan = now

            // Step 1: Get raw process data (EXPENSIVE — scans all PIDs)
            let rawProcesses = processMonitor.sampleProcesses(systemPowerW: metrics.sysPowerW)

            // Step 2: Apply proportional attribution
            let attributed = attributionEngine.attribute(processInfos: rawProcesses, metrics: metrics)
            correctionFactor = attributionEngine.averageCorrectionFactor(attributed: attributed)

            // Step 3: Record in history and apply averaging
            recordHistory(attributed, at: now)

            let averaged: [AttributedPower]
            if averagingSeconds > 0 {
                averaged = applyAveraging(attributed, windowSeconds: averagingSeconds, now: now)
            } else {
                averaged = attributed
            }

            attributedProcesses = averaged

            // Step 4: Group by coalition
            coalitions = coalitionGrouper.group(rawProcesses, systemPowerW: metrics.sysPowerW)
        }
    }

    /// Terminate an attributed process.
    func terminateProcess(_ info: AttributedPower) -> Bool {
        terminator.terminateAll(pids: info.pids) > 0
    }

    /// Terminate a process from raw info.
    func terminateProcess(_ info: ProcessPowerInfo) -> Bool {
        terminator.terminateAll(pids: info.pids) > 0
    }

    // MARK: - Averaging Logic

    private func recordHistory(_ processes: [AttributedPower], at time: Date) {
        historyLock.lock()
        defer { historyLock.unlock() }

        for proc in processes {
            if processHistory[proc.name] == nil {
                processHistory[proc.name] = []
            }
            processHistory[proc.name]!.append((time, proc.totalWatts))
        }
    }

    private func applyAveraging(_ current: [AttributedPower], windowSeconds: Int, now: Date) -> [AttributedPower] {
        historyLock.lock()
        defer { historyLock.unlock() }

        let cutoff = now.addingTimeInterval(-TimeInterval(windowSeconds))

        return current.map { proc in
            guard let history = processHistory[proc.name] else { return proc }
            let relevant = history.filter { $0.0 >= cutoff }
            guard !relevant.isEmpty else { return proc }

            let avgWatts = relevant.map(\.1).reduce(0, +) / Double(relevant.count)

            // Scale components proportionally to maintain the breakdown
            let scale = proc.totalWatts > 0.0001 ? avgWatts / proc.totalWatts : 1.0
            let sysPower = proc.percentOfSystem > 0 ? proc.percentOfSystem / proc.totalWatts * avgWatts : 0

            return AttributedPower(
                id: proc.id,
                name: proc.name,
                pids: proc.pids,
                cpuWatts: proc.cpuWatts * scale,
                dramWatts: proc.dramWatts * scale,
                gpuWatts: proc.gpuWatts * scale,
                storageWatts: proc.storageWatts * scale,
                percentOfSystem: sysPower,
                memoryBytes: proc.memoryBytes,
                pidCount: proc.pidCount,
                rawCpuWatts: proc.rawCpuWatts
            )
        }.sorted { $0.totalWatts > $1.totalWatts }
    }

    private func pruneHistory() {
        historyLock.lock()
        defer { historyLock.unlock() }

        let cutoff = Date().addingTimeInterval(-maxHistorySeconds)
        for (name, entries) in processHistory {
            processHistory[name] = entries.filter { $0.0 >= cutoff }
            if processHistory[name]?.isEmpty == true {
                processHistory.removeValue(forKey: name)
            }
        }
    }
}
