import Foundation

/// Result of a single calibration run for one app.
struct CalibrationResult: Codable, Equatable {
    let appName: String
    let coefficient: Double          // multiplier: real_power / rusage_power
    let baselinePowerW: Double       // system power WITH app running
    let postBaselinePowerW: Double   // system power WITHOUT app
    let deltaPowerW: Double          // real impact = baseline - postBaseline
    let rusagePowerW: Double         // what proc_pid_rusage reported
    let timestamp: Date
    let settleTimeSeconds: Double    // how long it took to stabilize
    let variancePct: Double          // power reading variance at end of settle

    /// Whether this calibration is considered reliable.
    var isReliable: Bool {
        variancePct < 10.0 && deltaPowerW > 0.01 && coefficient > 0.5 && coefficient < 100
    }
}

/// Current state of the calibration process.
enum CalibrationState: Equatable {
    case idle
    case measuringBaseline(progress: Double)       // 0.0 → 1.0
    case waitingForTermination
    case settling(elapsedSeconds: Double)
    case measuringPostBaseline(progress: Double)
    case computing
    case completed(CalibrationResult)
    case failed(String)
}

/// Stored calibration data (persisted to disk).
struct CalibrationStore: Codable {
    var globalCoefficient: Double
    var appCoefficients: [String: CalibrationResult]
    var lastCalibratedAt: Date?

    static let `default` = CalibrationStore(
        globalCoefficient: 1.0,
        appCoefficients: [:],
        lastCalibratedAt: nil
    )
}
