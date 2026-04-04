import Foundation

/// Production implementation of `ProcessRunning`.
/// Wraps Foundation.Process for subprocess execution.
final class ProcessRunner: ProcessRunning {

    func runSync(executablePath: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw AppError.processSpawnFailed(
                    "\(executablePath) exited with status \(process.terminationStatus)"
                )
            }
            return data
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.processSpawnFailed(error.localizedDescription)
        }
    }

    func findExecutable(name: String, searchPaths: [String]) -> String? {
        // Check known paths first
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fallback: `which` command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (path?.isEmpty == false) ? path : nil
            }
        } catch {
            // which command failed — that's OK
        }

        return nil
    }

    func createStreamingProcess(
        executablePath: String,
        arguments: [String]
    ) -> (Process, Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return (process, pipe)
    }
}
