import XCTest
import Combine
@testable import PowerBarPro

final class MacMonServiceTests: XCTestCase {

    var mockRunner: MockProcessRunner!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockRunner = MockProcessRunner()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        mockRunner = nil
        super.tearDown()
    }

    // MARK: - startMonitoring

    func testStartMonitoring_macmonNotFound_emitsError() {
        mockRunner.stubbedExecutablePath = nil // macmon not found
        let service = MacMonService(processRunner: mockRunner)

        let exp = expectation(description: "error emitted")

        service.errorPublisher
            .dropFirst() // skip initial nil
            .first()
            .sink { error in
                XCTAssertEqual(error, .macmonNotFound)
                exp.fulfill()
            }
            .store(in: &cancellables)

        service.startMonitoring()

        wait(for: [exp], timeout: 2.0)
    }

    func testStartMonitoring_macmonNotFound_staysNotRunning() {
        mockRunner.stubbedExecutablePath = nil
        let service = MacMonService(processRunner: mockRunner)

        service.startMonitoring()

        let exp = expectation(description: "check running state")
        service.isRunningPublisher
            .first()
            .sink { isRunning in
                XCTAssertFalse(isRunning)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Initial state

    func testInitialState_notRunning() {
        let service = MacMonService(processRunner: mockRunner)

        let exp = expectation(description: "initial state")
        service.isRunningPublisher
            .first()
            .sink { isRunning in
                XCTAssertFalse(isRunning)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    func testInitialState_noMetrics() {
        let service = MacMonService(processRunner: mockRunner)

        let exp = expectation(description: "initial metrics")
        service.metricsPublisher
            .first()
            .sink { metrics in
                XCTAssertNil(metrics)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    func testInitialState_noError() {
        let service = MacMonService(processRunner: mockRunner)

        let exp = expectation(description: "initial error")
        service.errorPublisher
            .first()
            .sink { error in
                XCTAssertNil(error)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - stopMonitoring

    func testStopMonitoring_whenNotRunning_noOp() {
        let service = MacMonService(processRunner: mockRunner)

        // Should not crash
        service.stopMonitoring()

        let exp = expectation(description: "still not running")
        service.isRunningPublisher
            .first()
            .sink { isRunning in
                XCTAssertFalse(isRunning)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - setUpdateInterval

    func testSetUpdateInterval_whenNotRunning_updatesInternally() {
        let service = MacMonService(processRunner: mockRunner)

        // Should not crash, just stores the value
        service.setUpdateInterval(500)

        // Verify it's still not running
        let exp = expectation(description: "not running")
        service.isRunningPublisher
            .first()
            .sink { isRunning in
                XCTAssertFalse(isRunning)
                exp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Double start prevention

    func testStartMonitoring_doubleCall_noOp() {
        // If macmon is found, first call starts, second should be no-op
        mockRunner.stubbedExecutablePath = "/opt/homebrew/bin/macmon"
        let service = MacMonService(processRunner: mockRunner)

        // The process won't actually run (mock returns a Process but doesn't set a valid executable)
        // We're testing the guard logic
        service.startMonitoring()
        // Second call should be guarded by isRunning check
        service.startMonitoring()

        // Clean up
        service.stopMonitoring()
    }
}
