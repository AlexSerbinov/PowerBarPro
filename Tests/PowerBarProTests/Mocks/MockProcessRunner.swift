import Foundation
@testable import PowerBarPro

/// Mock process runner for testing. Returns pre-configured responses.
final class MockProcessRunner: ProcessRunning {

    var stubbedRunSyncResult: Data?
    var stubbedRunSyncError: AppError?
    var stubbedExecutablePath: String?
    private(set) var runSyncCalls: [(path: String, args: [String])] = []

    func runSync(executablePath: String, arguments: [String]) throws -> Data {
        runSyncCalls.append((path: executablePath, args: arguments))
        if let error = stubbedRunSyncError {
            throw error
        }
        return stubbedRunSyncResult ?? Data()
    }

    func findExecutable(name: String, searchPaths: [String]) -> String? {
        stubbedExecutablePath
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
        return (process, pipe)
    }
}
