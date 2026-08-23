import Foundation
import Darwin

/// Production implementation of `ProcessTerminating`.
/// Sends POSIX signals to terminate processes by PID.
final class ProcessTerminator: ProcessTerminating {

    func terminate(pid: pid_t) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    func terminateAll(pids: [pid_t]) -> Int {
        pids.filter { terminate(pid: $0) }.count
    }
}
