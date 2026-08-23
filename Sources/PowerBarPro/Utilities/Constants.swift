import Foundation

/// App-wide constants. Centralised to avoid magic numbers.
enum Constants {

    enum MacPow {
        static let searchPaths = [
            "/opt/homebrew/bin/macpow",
            "/usr/local/bin/macpow",
            "/usr/bin/macpow"
        ]
        static let binaryName = "macpow"
    }

    enum MacMon {
        static let searchPaths = [
            "/opt/homebrew/bin/macmon",
            "/usr/local/bin/macmon",
            "/usr/bin/macmon"
        ]
        static let binaryName = "macmon"
    }

    enum Battery {
        /// ioreg command path.
        static let ioregPath = "/usr/sbin/ioreg"
        /// Minimum power (W) for reliable time-remaining calculation.
        static let minimumReliablePowerW = 0.1
    }

    enum Defaults {
        static let updateIntervalMs = 1000
        static let displayMode: DisplayMode = .average(seconds: 3)
        static let batteryDisplayMode: DisplayMode = .average(seconds: 300)
        static let maxHistoryDuration: TimeInterval = 21600  // 6 hours

        static let availableIntervals = [100, 250, 500, 1000, 2500]
        static let availableAveragePeriods = [3, 10, 30, 60, 300, 600, 1800, 3600, 0]
        static let processAveragingSeconds = 30  // Default: 30s averaging for process list
        static let availableProcessAveragingPeriods = [0, 5, 10, 30, 60, 300]  // 0 = instant
        static let alertThresholdW = 25  // Power-hog alert threshold
    }

    enum UI {
        static let menuBarFontSize: CGFloat = 13
    }
}
