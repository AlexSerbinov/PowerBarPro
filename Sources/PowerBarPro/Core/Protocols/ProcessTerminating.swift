import Foundation
import Darwin

/// Abstraction over process termination via signals.
/// Enables testing without actually killing processes.
protocol ProcessTerminating {
    /// Send SIGTERM to a single process.
    /// - Returns: `true` if the signal was delivered successfully.
    func terminate(pid: pid_t) -> Bool

    /// Send SIGTERM to multiple processes.
    /// - Returns: The number of processes that were successfully signalled.
    func terminateAll(pids: [pid_t]) -> Int
}
