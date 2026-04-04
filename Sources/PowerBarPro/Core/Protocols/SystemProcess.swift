import Foundation

/// Abstraction over Process() for launching system commands.
/// Enables testing without actually spawning subprocesses.
protocol ProcessRunning {
    /// Run a command synchronously and return stdout data.
    /// Throws `AppError.processSpawnFailed` on failure.
    func runSync(executablePath: String, arguments: [String]) throws -> Data

    /// Locate a binary by checking known paths then falling back to `which`.
    func findExecutable(name: String, searchPaths: [String]) -> String?

    /// Create a long-running process with streaming stdout.
    /// Returns (Process, Pipe) so the caller controls lifecycle.
    func createStreamingProcess(
        executablePath: String,
        arguments: [String]
    ) -> (Process, Pipe)
}
