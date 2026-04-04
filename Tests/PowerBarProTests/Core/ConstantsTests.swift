import XCTest
@testable import PowerBarPro

/// Tests for Constants — validates contract values that other code relies on.
/// If someone accidentally changes a constant, these tests catch it.
final class ConstantsTests: XCTestCase {

    // MARK: - MacMon

    func testMacMonSearchPaths_containsHomebrew() {
        XCTAssertTrue(Constants.MacMon.searchPaths.contains("/opt/homebrew/bin/macmon"))
    }

    func testMacMonSearchPaths_containsUsrLocal() {
        XCTAssertTrue(Constants.MacMon.searchPaths.contains("/usr/local/bin/macmon"))
    }

    func testMacMonBinaryName() {
        XCTAssertEqual(Constants.MacMon.binaryName, "macmon")
    }

    // MARK: - Battery

    func testBatteryIoregPath() {
        XCTAssertEqual(Constants.Battery.ioregPath, "/usr/sbin/ioreg")
    }

    func testMinimumReliablePowerW() {
        XCTAssertEqual(Constants.Battery.minimumReliablePowerW, 0.1, accuracy: 0.001)
    }

    // MARK: - Defaults

    func testDefaultUpdateInterval() {
        XCTAssertEqual(Constants.Defaults.updateIntervalMs, 1000)
    }

    func testDefaultDisplayMode() {
        XCTAssertEqual(Constants.Defaults.displayMode, .average(seconds: 3))
    }

    func testDefaultBatteryDisplayMode() {
        XCTAssertEqual(Constants.Defaults.batteryDisplayMode, .average(seconds: 300))
    }

    func testMaxHistoryDuration_6hours() {
        XCTAssertEqual(Constants.Defaults.maxHistoryDuration, 21600)
    }

    func testAvailableIntervals_sorted() {
        let intervals = Constants.Defaults.availableIntervals
        XCTAssertEqual(intervals, intervals.sorted())
    }

    func testAvailableIntervals_allPositive() {
        for interval in Constants.Defaults.availableIntervals {
            XCTAssertGreaterThan(interval, 0)
        }
    }

    func testAvailableAveragePeriods_contains0ForAllTime() {
        XCTAssertTrue(Constants.Defaults.availableAveragePeriods.contains(0))
    }

    func testAvailableAveragePeriods_containsCommonValues() {
        let periods = Constants.Defaults.availableAveragePeriods
        XCTAssertTrue(periods.contains(3))    // 3 seconds
        XCTAssertTrue(periods.contains(60))   // 1 minute
        XCTAssertTrue(periods.contains(300))  // 5 minutes
        XCTAssertTrue(periods.contains(3600)) // 1 hour
    }

    // MARK: - UI

    func testMenuBarFontSize() {
        XCTAssertEqual(Constants.UI.menuBarFontSize, 13)
    }
}
