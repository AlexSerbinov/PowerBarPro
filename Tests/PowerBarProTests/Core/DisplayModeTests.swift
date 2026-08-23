import XCTest
@testable import PowerBarPro

final class DisplayModeTests: XCTestCase {

    // MARK: - displayName

    func testDisplayName_instant() {
        XCTAssertEqual(DisplayMode.instant.displayName, "Instant")
    }

    func testDisplayName_seconds() {
        XCTAssertEqual(DisplayMode.average(seconds: 3).displayName, "3s")
        XCTAssertEqual(DisplayMode.average(seconds: 30).displayName, "30s")
    }

    func testDisplayName_minutes() {
        XCTAssertEqual(DisplayMode.average(seconds: 60).displayName, "1min")
        XCTAssertEqual(DisplayMode.average(seconds: 300).displayName, "5min")
        XCTAssertEqual(DisplayMode.average(seconds: 3600).displayName, "60min")
    }

    func testDisplayName_allTime() {
        XCTAssertEqual(DisplayMode.average(seconds: 0).displayName, "All Time")
    }

    func testDisplayName_nonStandardMinutes() {
        // 90 seconds = 1m30s (not truncated to "1min")
        XCTAssertEqual(DisplayMode.average(seconds: 90).displayName, "1m30s")
        XCTAssertEqual(DisplayMode.average(seconds: 150).displayName, "2m30s")
    }

    // MARK: - Equatable

    func testEquatable_instant() {
        XCTAssertEqual(DisplayMode.instant, DisplayMode.instant)
    }

    func testEquatable_averageSame() {
        XCTAssertEqual(DisplayMode.average(seconds: 60), DisplayMode.average(seconds: 60))
    }

    func testEquatable_averageDifferent() {
        XCTAssertNotEqual(DisplayMode.average(seconds: 30), DisplayMode.average(seconds: 60))
    }

    func testEquatable_instantVsAverage() {
        XCTAssertNotEqual(DisplayMode.instant, DisplayMode.average(seconds: 0))
    }

    // MARK: - Codable

    func testCodable_instant() throws {
        let original = DisplayMode.instant
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodable_average() throws {
        let original = DisplayMode.average(seconds: 300)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodable_allTime() throws {
        let original = DisplayMode.average(seconds: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
