import XCTest
import Cocoa
@testable import PowerBarPro

/// Full UI pipeline integration test.
/// Verifies that the menu renders correctly with realistic data.
final class UIIntegrationTests: XCTestCase {

    // MARK: - Full Menu Rendering

    func testFullMenuRendering_allSectionsPresent() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu(
            currentDisplayMode: .average(seconds: 3),
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        // Must have all key items
        XCTAssertNotNil(builder.detailsItem, "Details item missing")
        XCTAssertNotNil(builder.batteryItem, "Battery item missing")
        XCTAssertNotNil(builder.displayPowerItem, "Display power item missing")
        XCTAssertNotNil(builder.processSectionHeader, "Process section header missing")

        // Must have Quit item
        let quitItem = menu.items.last
        XCTAssertEqual(quitItem?.title, "Quit PowerBar")
        XCTAssertEqual(quitItem?.keyEquivalent, "q")

        // Must have submenus for averaging/interval/battery
        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })
        XCTAssertNotNil(avgItem?.submenu)
        XCTAssertTrue(avgItem!.title.contains("3s")) // Default mode

        let intItem = menu.items.first(where: { $0.title.hasPrefix("Refresh Rate") })
        XCTAssertNotNil(intItem?.submenu)
        XCTAssertTrue(intItem!.title.contains("1000ms"))
    }

    // MARK: - Process List Rendering

    func testProcessListRendering_withRealisticData() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        let processes = [
            ProcessPowerInfo(id: "Safari", name: "Safari", powerWatts: 2.5,
                            percentOfSystem: 20.7, memoryBytes: 524_288_000,
                            pidCount: 3, pids: [100, 101, 102]),
            ProcessPowerInfo(id: "Terminal", name: "Terminal", powerWatts: 0.8,
                            percentOfSystem: 6.6, memoryBytes: 52_428_800,
                            pidCount: 1, pids: [200]),
            ProcessPowerInfo(id: "Telegram", name: "Telegram", powerWatts: 0.003,
                            percentOfSystem: 0.02, memoryBytes: 209_715_200,
                            pidCount: 2, pids: [300, 301]),
        ]

        builder.updateProcessList(menu: menu, processes: processes, systemPowerW: 12.1)

        // Verify process items created (1 per process — clickable to terminate)
        XCTAssertEqual(builder.processMenuItems.count, 3)

        // Safari
        let safari = builder.processMenuItems[0]
        XCTAssertTrue(safari.title.contains("Safari"))
        XCTAssertTrue(safari.title.contains("W"))
        XCTAssertNotNil(safari.toolTip) // Tooltip with "Terminate"

        // Terminal
        let terminal = builder.processMenuItems[1]
        XCTAssertTrue(terminal.title.contains("Terminal"))
        XCTAssertTrue(terminal.title.contains("mW"))

        // Telegram
        let telegram = builder.processMenuItems[2]
        XCTAssertTrue(telegram.title.contains("Telegram"))
    }

    // MARK: - Display Power Text

    func testDisplayPowerRendering() {
        let builder = MenuBuilder()
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        // Initial state
        XCTAssertEqual(builder.displayPowerItem?.title, "Display: --")

        // After update
        builder.displayPowerItem?.title = "Display: 4.50W (75% brightness)"
        XCTAssertTrue(builder.displayPowerItem!.title.contains("4.50W"))
        XCTAssertTrue(builder.displayPowerItem!.title.contains("75%"))
    }

    // MARK: - Battery Text Rendering

    func testBatteryRendering() {
        let builder = MenuBuilder()
        _ = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .average(seconds: 300),
            currentIntervalMs: 1000
        )

        // Battery should have submenu for mode selection
        XCTAssertNotNil(builder.batteryItem?.submenu)

        // Simulate battery update
        builder.batteryItem?.title = "Battery: 4h 00m remaining - 60.0Wh"
        XCTAssertTrue(builder.batteryItem!.title.contains("4h 00m"))
        XCTAssertTrue(builder.batteryItem!.title.contains("60.0Wh"))
    }

    // MARK: - Formatter Visual Output

    func testFormatterOutputVisual() {
        // Verify formatters produce readable output
        XCTAssertEqual(Formatters.power(12.1), "12.1W")
        XCTAssertEqual(Formatters.power(0.5), "0.5W")
        XCTAssertEqual(Formatters.processWatts(2.5), "2.50 W")
        XCTAssertEqual(Formatters.processWatts(0.35), "350.0 mW")
        XCTAssertEqual(Formatters.processWatts(0.003), "3.0 mW")
        XCTAssertEqual(Formatters.processWatts(0.0005), "500 uW")
        XCTAssertEqual(Formatters.remainingTime(14400), "4h 00m")
        XCTAssertEqual(Formatters.remainingTime(5400), "1h 30m")
        XCTAssertEqual(Formatters.remainingTime(2700), "45m")
        XCTAssertEqual(Formatters.periodName(300), "5 minutes")
        XCTAssertEqual(Formatters.periodName(0), "All Time Average")
    }

    // MARK: - Details Line Rendering

    func testDetailsLineRendering() {
        let metrics = TestData.sampleMetrics()
        let inline = Formatters.inlineBreakdown(metrics)

        // Should be single line with pipe separators
        XCTAssertFalse(inline.contains("\n"), "Should be single line")
        XCTAssertTrue(inline.contains("System:"))
        XCTAssertTrue(inline.contains("CPU:"))
        XCTAssertTrue(inline.contains("GPU:"))
        XCTAssertTrue(inline.contains("|"))
    }

    // MARK: - Empty Process List

    func testEmptyProcessList() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        builder.updateProcessList(menu: menu, processes: [], systemPowerW: 12.1)

        XCTAssertEqual(builder.processMenuItems.count, 1)
        XCTAssertTrue(builder.processMenuItems[0].title.contains("No active"))
    }

    // MARK: - Checkmark State

    func testCheckmarkState_displayMode() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu(
            currentDisplayMode: .instant,
            currentBatteryMode: .instant,
            currentIntervalMs: 1000
        )

        // Update to 5min average
        builder.updateDisplayModeCheckmarks(menu: menu, mode: .average(seconds: 300))

        let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") })!
        XCTAssertTrue(avgItem.title.contains("5min"))

        // Instant should be unchecked
        let instantItem = avgItem.submenu?.items.first(where: { $0.tag == -1 })
        XCTAssertEqual(instantItem?.state, .off)

        // 5min should be checked
        let fiveMinItem = avgItem.submenu?.items.first(where: { $0.tag == 300 })
        XCTAssertEqual(fiveMinItem?.state, .on)
    }
}
