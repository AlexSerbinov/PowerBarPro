import Foundation

/// Typed errors for the application. Provides structured error handling
/// instead of raw string messages.
enum AppError: Error, Equatable, LocalizedError {
    case macmonNotFound
    case macmonTerminated(status: Int32)
    case macmonStartFailed(String)
    case jsonDecodingFailed(String)
    case batteryInfoUnavailable
    case processSpawnFailed(String)

    var errorDescription: String? {
        switch self {
        case .macmonNotFound:
            return "macmon is not installed. Install via: brew install macmon"
        case .macmonTerminated(let status):
            return "macmon terminated unexpectedly (exit code \(status))"
        case .macmonStartFailed(let reason):
            return "Failed to start macmon: \(reason)"
        case .jsonDecodingFailed(let detail):
            return "JSON decode error: \(detail)"
        case .batteryInfoUnavailable:
            return "Battery information unavailable"
        case .processSpawnFailed(let reason):
            return "Process failed: \(reason)"
        }
    }
}
