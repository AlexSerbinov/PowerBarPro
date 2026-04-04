import XCTest
@testable import PowerBarPro

final class ProcessRunnerTests: XCTestCase {

    var runner: ProcessRunner!

    override func setUp() {
        super.setUp()
        runner = ProcessRunner()
    }

    // MARK: - runSync

    func testRunSync_echo() throws {
        let data = try runner.runSync(
            executablePath: "/bin/echo",
            arguments: ["hello"]
        )
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(output, "hello")
    }

    func testRunSync_nonExistentBinary_throws() {
        XCTAssertThrowsError(try runner.runSync(
            executablePath: "/usr/bin/nonexistent_binary_12345",
            arguments: []
        ))
    }

    func testRunSync_failingCommand_throws() {
        XCTAssertThrowsError(try runner.runSync(
            executablePath: "/bin/ls",
            arguments: ["/nonexistent_path_12345"]
        ))
    }

    // MARK: - findExecutable

    func testFindExecutable_knownPath() {
        let path = runner.findExecutable(
            name: "ls",
            searchPaths: ["/bin/ls"]
        )
        XCTAssertEqual(path, "/bin/ls")
    }

    func testFindExecutable_fallbackToWhich() {
        // Empty search paths, should fall back to `which`
        let path = runner.findExecutable(
            name: "ls",
            searchPaths: []
        )
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.hasSuffix("ls"))
    }

    func testFindExecutable_notFound() {
        let path = runner.findExecutable(
            name: "nonexistent_binary_12345",
            searchPaths: ["/nonexistent/path"]
        )
        XCTAssertNil(path)
    }

    // MARK: - createStreamingProcess

    func testCreateStreamingProcess_returnsValidProcessAndPipe() {
        let (process, pipe) = runner.createStreamingProcess(
            executablePath: "/bin/echo",
            arguments: ["test"]
        )
        XCTAssertNotNil(process.executableURL)
        XCTAssertEqual(process.arguments, ["test"])
        XCTAssertNotNil(pipe)
    }
}
