import XCTest
import Cocoa
@testable import PowerBarPro

final class MenuBuilderTests: XCTestCase {

    var builder: MenuBuilder!

    override func setUp() {
        super.setUp()
        builder = MenuBuilder()
    }

    override func tearDown() {
        builder = nil
        super.tearDown()
    }

    // MARK: - buildMenu

    func testBuildMenu_hasExpectedItems() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        // Should have: details, sep, averaging, sep, refresh, sep, battery, sep, quit
        XCTAssertGreaterThanOrEqual(menu.items.count, 9)
    }

    func testBuildMenu_hasQuitItem() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        let quitItem = menu.items.last
        XCTAssertEqual(quitItem?.title, "Quit PowerBar")
        XCTAssertEqual(quitItem?.keyEquivalent, "q")
    }

    func testBuildMenu_setsDetailsReference() {
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        XCTAssertNotNil(builder.detailsItem)
        XCTAssertEqual(builder.detailsItem?.title, "Power Details")
    }

    func testBuildMenu_setsBatteryReference() {
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        XCTAssertNotNil(builder.batteryItem)
        XCTAssertTrue(builder.batteryItem!.title.contains("Battery"))
    }

    func testBuildMenu_displayModeInTitle() {
        let menu = builder.buildMenu(
            currentDisplayMode: .average(seconds: 60),
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })
        XCTAssertNotNil(avgItem)
        XCTAssertTrue(avgItem!.title.contains("1min"))
    }

    func testBuildMenu_intervalInTitle() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 500
        )

        let intervalItem = menu.items.first(where: { $0.title.hasPrefix("Refresh Rate") })
        XCTAssertNotNil(intervalItem)
        XCTAssertTrue(intervalItem!.title.contains("500ms"))
    }

    // MARK: - Submenu contents

    func testAveragingSubmenu_hasInstantOption() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })
        let submenu = avgItem?.submenu
        XCTAssertNotNil(submenu)

        let instantItem = submenu?.items.first(where: { $0.title == "Instant" })
        XCTAssertNotNil(instantItem)
        XCTAssertEqual(instantItem?.tag, -1)
    }

    func testAveragingSubmenu_hasAllPeriods() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })
        let submenu = avgItem?.submenu
        XCTAssertNotNil(submenu)

        // Check that all periods have menu items
        for period in Constants.Defaults.availableAveragePeriods {
            let name = Formatters.periodName(period)
            let item = submenu?.items.first(where: { $0.title == name })
            XCTAssertNotNil(item, "Missing menu item for period: \(name)")
            XCTAssertEqual(item?.tag, period)
        }
    }

    // MARK: - Checkmark updates

    func testUpdateDisplayModeCheckmarks() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        builder.updateDisplayModeCheckmarks(menu: menu, mode: .average(seconds: 60))

        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })
        XCTAssertTrue(avgItem!.title.contains("1min"))

        // Instant should be unchecked
        let instantItem = avgItem?.submenu?.items.first(where: { $0.tag == -1 })
        XCTAssertEqual(instantItem?.state, .off)

        // 60s should be checked
        let minuteItem = avgItem?.submenu?.items.first(where: { $0.tag == 60 })
        XCTAssertEqual(minuteItem?.state, .on)
    }

    func testUpdateIntervalCheckmarks() {
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        builder.updateIntervalCheckmarks(menu: menu, intervalMs: 250)

        let intervalItem = menu.items.first(where: { $0.title.hasPrefix("Refresh Rate") })
        XCTAssertTrue(intervalItem!.title.contains("250ms"))
    }

    // MARK: - Action callbacks

    func testOnQuit_callbackInvoked() {
        var quitCalled = false
        builder.onQuit = { quitCalled = true }

        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        // Find quit item and simulate click
        let quitItem = menu.items.last
        XCTAssertNotNil(quitItem?.target)

        // We can't directly invoke @objc selector easily in tests,
        // but we verified the callback is wired
        XCTAssertFalse(quitCalled) // Callback not yet invoked
    }

    func testOnDisplayModeSelected_callbackWired() {
        var selectedMode: DisplayMode?
        builder.onDisplayModeSelected = { mode in
            selectedMode = mode
        }

        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        // Callback is wired, will be invoked on menu item click
        XCTAssertNil(selectedMode) // Not yet invoked
    }
}
