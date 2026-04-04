import XCTest
@testable import PowerBarPro

final class FormattersTests: XCTestCase {

    // MARK: - power()

    func testPower_normal() {
        XCTAssertEqual(Formatters.power(12.1), "12.1W")
    }

    func testPower_zero() {
        XCTAssertEqual(Formatters.power(0.0), "0.0W")
    }

    func testPower_high() {
        XCTAssertEqual(Formatters.power(95.7), "95.7W")
    }

    func testPower_fractional() {
        XCTAssertEqual(Formatters.power(3.14159), "3.1W")
    }

    // MARK: - remainingTime()

    func testRemainingTime_hoursAndMinutes() {
        XCTAssertEqual(Formatters.remainingTime(16200), "4h 30m")
    }

    func testRemainingTime_exactHours() {
        XCTAssertEqual(Formatters.remainingTime(7200), "2h 00m")
    }

    func testRemainingTime_minutesOnly() {
        XCTAssertEqual(Formatters.remainingTime(2700), "45m")
    }

    func testRemainingTime_oneMinute() {
        XCTAssertEqual(Formatters.remainingTime(60), "1m")
    }

    func testRemainingTime_lessThanMinute() {
        XCTAssertEqual(Formatters.remainingTime(30), "0m")
    }

    func testRemainingTime_zero() {
        XCTAssertEqual(Formatters.remainingTime(0), "0m")
    }

    func testRemainingTime_large() {
        XCTAssertEqual(Formatters.remainingTime(44100), "12h 15m")
    }

    // MARK: - detailedBreakdown()

    func testDetailedBreakdown_containsAllComponents() {
        let metrics = TestData.sampleMetrics()
        let breakdown = Formatters.detailedBreakdown(metrics)

        XCTAssertTrue(breakdown.contains("System: 12.1W"))
        XCTAssertTrue(breakdown.contains("CPU: 3.2W"))
        XCTAssertTrue(breakdown.contains("GPU: 1.8W"))
        XCTAssertTrue(breakdown.contains("ANE: 0.0W"))
        XCTAssertTrue(breakdown.contains("RAM: 0.8W"))
    }

    // MARK: - inlineBreakdown()

    func testInlineBreakdown_singleLine() {
        let metrics = TestData.sampleMetrics()
        let inline = Formatters.inlineBreakdown(metrics)

        XCTAssertFalse(inline.contains("\n"))
        XCTAssertTrue(inline.contains("System: 12.1W"))
        XCTAssertTrue(inline.contains("|"))
    }

    // MARK: - periodName()

    func testPeriodName_allTime() {
        XCTAssertEqual(Formatters.periodName(0), "All Time Average")
    }

    func testPeriodName_seconds() {
        XCTAssertEqual(Formatters.periodName(3), "3 seconds")
        XCTAssertEqual(Formatters.periodName(10), "10 seconds")
        XCTAssertEqual(Formatters.periodName(30), "30 seconds")
    }

    func testPeriodName_minutes() {
        XCTAssertEqual(Formatters.periodName(60), "1 minute")
        XCTAssertEqual(Formatters.periodName(300), "5 minutes")
        XCTAssertEqual(Formatters.periodName(600), "10 minutes")
        XCTAssertEqual(Formatters.periodName(1800), "30 minutes")
        XCTAssertEqual(Formatters.periodName(3600), "1 hour")
    }

    func testPeriodName_arbitrary() {
        XCTAssertEqual(Formatters.periodName(7), "7 seconds")
        XCTAssertEqual(Formatters.periodName(120), "2 minutes")
    }
}
