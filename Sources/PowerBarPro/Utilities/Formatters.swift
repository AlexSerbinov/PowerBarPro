import Foundation

/// Pure formatting functions — no side effects, fully testable.
enum Formatters {

    /// Format watts for menu bar display: "12.1W"
    static func power(_ watts: Double) -> String {
        String(format: "%.1fW", watts)
    }

    /// Format time interval as "Xh YYm" or "Xm" for display.
    static func remainingTime(_ interval: TimeInterval) -> String {
        let clamped = max(interval, 0)
        let hours = Int(clamped / 3600)
        let minutes = Int((clamped.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    /// Multi-line power breakdown for tooltips/details.
    static func detailedBreakdown(_ metrics: SystemMetrics) -> String {
        """
        System: \(power(metrics.sysPower))
        CPU: \(power(metrics.cpuPower))
        GPU: \(power(metrics.gpuPower))
        ANE: \(power(metrics.anePower))
        RAM: \(power(metrics.ramPower))
        """
    }

    /// Single-line power breakdown for menu items.
    static func inlineBreakdown(_ metrics: SystemMetrics) -> String {
        "System: \(power(metrics.sysPower)) | CPU: \(power(metrics.cpuPower)) | GPU: \(power(metrics.gpuPower)) | ANE: \(power(metrics.anePower)) | RAM: \(power(metrics.ramPower))"
    }

    /// Human-friendly name for averaging periods.
    static func periodName(_ seconds: Int) -> String {
        if seconds == 0 { return "All Time Average" }
        switch seconds {
        case 3: return "3 seconds"
        case 5: return "5 seconds"
        case 10: return "10 seconds"
        case 30: return "30 seconds"
        case 60: return "1 minute"
        case 300: return "5 minutes"
        case 600: return "10 minutes"
        case 1800: return "30 minutes"
        case 3600: return "1 hour"
        default:
            if seconds >= 60 { return "\(seconds / 60) minutes" }
            return "\(seconds) seconds"
        }
    }

    /// Format process watts with adaptive units (uW, mW, W).
    static func processWatts(_ watts: Double) -> String {
        let w = max(watts, 0)
        if w < 0.001 {
            return String(format: "%.0f uW", w * 1_000_000)
        } else if w < 1.0 {
            return String(format: "%.1f mW", w * 1000)
        } else {
            return String(format: "%.2f W", w)
        }
    }
}
