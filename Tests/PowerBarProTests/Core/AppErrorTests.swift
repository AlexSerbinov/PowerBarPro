import XCTest
@testable import PowerBarPro

final class AppErrorTests: XCTestCase {

    // MARK: - errorDescription

    func testMacmonNotFound_description() {
        let error = AppError.macmonNotFound
        XCTAssertTrue(error.localizedDescription.contains("macmon"))
        XCTAssertTrue(error.localizedDescription.contains("brew install"))
    }

    func testMacmonTerminated_description() {
        let error = AppError.macmonTerminated(status: 1)
        XCTAssertTrue(error.localizedDescription.contains("terminated"))
        XCTAssertTrue(error.localizedDescription.contains("1"))
    }

    func testMacmonTerminated_differentCodes() {
        let error127 = AppError.macmonTerminated(status: 127)
        XCTAssertTrue(error127.localizedDescription.contains("127"))

        let errorNeg = AppError.macmonTerminated(status: -9)
        XCTAssertTrue(errorNeg.localizedDescription.contains("-9"))
    }

    func testMacmonStartFailed_description() {
        let error = AppError.macmonStartFailed("permission denied")
        XCTAssertTrue(error.localizedDescription.contains("permission denied"))
    }

    func testJsonDecodingFailed_description() {
        let error = AppError.jsonDecodingFailed("missing key 'sys_power'")
        XCTAssertTrue(error.localizedDescription.contains("missing key"))
    }

    func testBatteryInfoUnavailable_description() {
        let error = AppError.batteryInfoUnavailable
        XCTAssertTrue(error.localizedDescription.contains("Battery"))
    }

    func testProcessSpawnFailed_description() {
        let error = AppError.processSpawnFailed("file not found")
        XCTAssertTrue(error.localizedDescription.contains("file not found"))
    }

    // MARK: - Equatable

    func testEquatable_sameCases() {
        XCTAssertEqual(AppError.macmonNotFound, AppError.macmonNotFound)
        XCTAssertEqual(AppError.batteryInfoUnavailable, AppError.batteryInfoUnavailable)
        XCTAssertEqual(
            AppError.macmonTerminated(status: 1),
            AppError.macmonTerminated(status: 1)
        )
    }

    func testEquatable_differentCases() {
        XCTAssertNotEqual(AppError.macmonNotFound, AppError.batteryInfoUnavailable)
        XCTAssertNotEqual(
            AppError.macmonTerminated(status: 1),
            AppError.macmonTerminated(status: 2)
        )
    }

    func testEquatable_differentPayloads() {
        XCTAssertNotEqual(
            AppError.macmonStartFailed("a"),
            AppError.macmonStartFailed("b")
        )
        XCTAssertNotEqual(
            AppError.jsonDecodingFailed("x"),
            AppError.jsonDecodingFailed("y")
        )
    }

    // MARK: - Error protocol conformance

    func testConformsToError() {
        let error: Error = AppError.macmonNotFound
        XCTAssertNotNil(error.localizedDescription)
    }

    func testConformsToLocalizedError() {
        let error: LocalizedError = AppError.macmonNotFound
        XCTAssertNotNil(error.errorDescription)
    }
}
