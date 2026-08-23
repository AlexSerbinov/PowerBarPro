import Foundation

/// Controls how power values are displayed in the menu bar.
///
/// - `instant`: Real-time reading from the latest macmon sample.
/// - `average(seconds:)`: Rolling average over the given window.
///   Special case: `seconds == 0` means all-time average.
enum DisplayMode: Equatable, Codable, Sendable {
    case instant
    case average(seconds: Int)

    /// Human-readable label for menus.
    var displayName: String {
        switch self {
        case .instant:
            return "Instant"
        case .average(let seconds):
            if seconds == 0 {
                return "All Time"
            } else if seconds >= 60 {
                let mins = seconds / 60
                let remainder = seconds % 60
                if remainder == 0 {
                    return "\(mins)min"
                } else {
                    return "\(mins)m\(remainder)s"
                }
            } else {
                return "\(seconds)s"
            }
        }
    }
}
