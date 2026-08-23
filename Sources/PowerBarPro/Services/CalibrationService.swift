import Foundation
import Combine

/// Automated calibration service that measures real app power impact
/// by comparing system power before and after terminating a target app.
///
/// Algorithm:
/// 1. BASELINE: Record 30s of system power with target app running (EMA smoothed)
/// 2. TERMINATE: Force-quit target app
/// 3. SETTLE: Wait for thermal/DVFS steady state (30-60s, variance <5%)
/// 4. POST-BASELINE: Record 30s of system power without app
/// 5. COMPUTE: coefficient = delta_power / rusage_power
final class CalibrationService: ObservableObject {

    // MARK: - Output

    @Published private(set) var state: CalibrationState = .idle
    @Published var store: CalibrationStore

    // MARK: - Config

    struct Config {
        let baselineDuration: TimeInterval      // seconds to measure baseline
        let postBaselineDuration: TimeInterval   // seconds to measure post-baseline
        let maxSettleTime: TimeInterval          // max seconds to wait for settling
        let settleVarianceThreshold: Double      // % variance to consider stable
        let settleWindowSeconds: TimeInterval    // seconds of window for variance check
        let emaAlpha: Double                     // EMA smoothing factor
        let discardInitialSeconds: TimeInterval  // seconds to discard after app kill (thermal inertia)

        static let `default` = Config(
            baselineDuration: 30,
            postBaselineDuration: 30,
            maxSettleTime: 60,
            settleVarianceThreshold: 5.0,
            settleWindowSeconds: 10,
            emaAlpha: 0.1,
            discardInitialSeconds: 15
        )
    }

    private let config: Config
    private let processTerminator: ProcessTerminating
    private let storageURL: URL

    // MARK: - Calibration state machine

    private var powerReadings: [PowerSample] = []
    private var baselineEMA: Double = 0
    private var postBaselineEMA: Double = 0
    private var targetAppName: String = ""
    private var targetPIDs: [pid_t] = []
    private var targetRusagePowerW: Double = 0
    private var settleStartTime: Date?

    private struct PowerSample {
        let watts: Double
        let timestamp: Date
    }

    // MARK: - Init

    init(
        processTerminator: ProcessTerminating,
        config: Config = .default,
        storageURL: URL? = nil
    ) {
        self.processTerminator = processTerminator
        self.config = config
        self.storageURL = storageURL ?? CalibrationService.defaultStorageURL()
        self.store = CalibrationService.loadStore(from: self.storageURL)
    }

    // MARK: - Public API

    /// Start calibration for a specific app.
    /// The app must be currently running.
    func startCalibration(
        appName: String,
        pids: [pid_t],
        currentRusagePowerW: Double
    ) {
        switch state {
        case .idle, .completed, .failed:
            break  // Can start new calibration
        default:
            return // Already running
        }

        targetAppName = appName
        targetPIDs = pids
        targetRusagePowerW = currentRusagePowerW
        powerReadings.removeAll()
        baselineEMA = 0
        postBaselineEMA = 0

        state = .measuringBaseline(progress: 0)
    }

    /// Feed a system power reading during calibration.
    /// Call this on every macpow update while calibration is active.
    func feedPowerReading(_ systemPowerW: Double) {
        let now = Date()
        let sample = PowerSample(watts: systemPowerW, timestamp: now)

        switch state {
        case .measuringBaseline:
            powerReadings.append(sample)
            baselineEMA = ema(baselineEMA, new: systemPowerW)

            let elapsed = powerReadings.count > 1
                ? now.timeIntervalSince(powerReadings.first!.timestamp)
                : 0
            let newProgress = min(elapsed / config.baselineDuration, 1.0)
            state = .measuringBaseline(progress: newProgress)

            if elapsed >= config.baselineDuration {
                terminateAndSettle()
            }

        case .settling:
            powerReadings.append(sample)
            postBaselineEMA = ema(postBaselineEMA, new: systemPowerW)

            let settleElapsed = now.timeIntervalSince(settleStartTime ?? now)

            // Skip initial thermal inertia period
            if settleElapsed < config.discardInitialSeconds {
                state = .settling(elapsedSeconds: settleElapsed)
                return
            }

            // Check if readings have stabilized
            let recentWindow = powerReadings.filter {
                now.timeIntervalSince($0.timestamp) < config.settleWindowSeconds
            }

            if recentWindow.count >= 3 {
                let variance = Self.variancePct(recentWindow.map(\.watts))
                if variance < config.settleVarianceThreshold {
                    // Settled! Start post-baseline measurement
                    powerReadings.removeAll()
                    state = .measuringPostBaseline(progress: 0)
                    return
                }
            }

            if settleElapsed >= config.maxSettleTime {
                // Timeout — proceed with whatever we have
                powerReadings.removeAll()
                state = .measuringPostBaseline(progress: 0)
            } else {
                state = .settling(elapsedSeconds: settleElapsed)
            }

        case .measuringPostBaseline:
            powerReadings.append(sample)
            postBaselineEMA = ema(postBaselineEMA, new: systemPowerW)

            let elapsed = powerReadings.count > 1
                ? now.timeIntervalSince(powerReadings.first!.timestamp)
                : 0
            let newProgress = min(elapsed / config.postBaselineDuration, 1.0)
            state = .measuringPostBaseline(progress: newProgress)

            if elapsed >= config.postBaselineDuration {
                computeResult()
            }

        default:
            break
        }
    }

    /// Cancel ongoing calibration.
    func cancel() {
        state = .idle
        powerReadings.removeAll()
    }

    /// Get calibration coefficient for an app (or global fallback).
    func coefficient(for appName: String) -> Double {
        if let appResult = store.appCoefficients[appName], appResult.isReliable {
            return appResult.coefficient
        }
        return store.globalCoefficient
    }

    // MARK: - Private

    private func terminateAndSettle() {
        state = .waitingForTermination

        // Force-kill all PIDs
        for pid in targetPIDs {
            _ = processTerminator.terminate(pid: pid)
        }

        // Start settling phase
        settleStartTime = Date()
        powerReadings.removeAll()
        postBaselineEMA = baselineEMA  // Start EMA from baseline level
        state = .settling(elapsedSeconds: 0)
    }

    private func computeResult() {
        state = .computing

        let postReadings = powerReadings.map(\.watts)
        let postAvg = postReadings.isEmpty ? 0 : postReadings.reduce(0, +) / Double(postReadings.count)
        let variance = Self.variancePct(postReadings)

        let delta = baselineEMA - postAvg
        let coefficient = targetRusagePowerW > 0.001
            ? delta / targetRusagePowerW
            : 1.0

        let settleTime = settleStartTime.map { Date().timeIntervalSince($0) } ?? 0

        let result = CalibrationResult(
            appName: targetAppName,
            coefficient: max(coefficient, 0.1), // Floor at 0.1 to avoid nonsense
            baselinePowerW: baselineEMA,
            postBaselinePowerW: postAvg,
            deltaPowerW: delta,
            rusagePowerW: targetRusagePowerW,
            timestamp: Date(),
            settleTimeSeconds: settleTime,
            variancePct: variance
        )

        // Store result
        store.appCoefficients[targetAppName] = result
        store.lastCalibratedAt = Date()

        // Recalculate global coefficient as median of all reliable per-app coefficients
        let reliableCoeffs = store.appCoefficients.values
            .filter(\.isReliable)
            .map(\.coefficient)
            .sorted()
        if !reliableCoeffs.isEmpty {
            store.globalCoefficient = reliableCoeffs[reliableCoeffs.count / 2] // Median
        }

        saveStore()
        state = .completed(result)
    }

    private func ema(_ current: Double, new: Double) -> Double {
        if current == 0 { return new }
        return current * (1 - config.emaAlpha) + new * config.emaAlpha
    }

    /// Calculate coefficient of variation as percentage.
    static func variancePct(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 100 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0.01 else { return 100 }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let stddev = sqrt(variance)
        return (stddev / mean) * 100
    }

    // MARK: - Persistence

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("PowerBarPro")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calibration.json")
    }

    private static func loadStore(from url: URL) -> CalibrationStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(CalibrationStore.self, from: data) else {
            return .default
        }
        return store
    }

    private func saveStore() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storageURL)
    }
}
