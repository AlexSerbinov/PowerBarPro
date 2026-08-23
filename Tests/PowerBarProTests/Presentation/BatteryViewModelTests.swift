import XCTest
@testable import PowerBarPro

final class BatteryViewModelTests: XCTestCase {

    var mockBattery: MockBatteryMonitor!
    var aggregator: PowerAggregator!
    var mockSettings: MockSettingsStore!
    var vm: BatteryViewModel!

    override func setUp() {
        super.setUp()
        mockBattery = MockBatteryMonitor()
        aggregator = PowerAggregator()
        mockSettings = MockSettingsStore(batteryDisplayMode: .instant)
        vm = BatteryViewModel(
            batteryMonitor: mockBattery,
            aggregator: aggregator,
            settings: mockSettings
        )
    }

    override func tearDown() {
        vm = nil
        mockBattery = nil
        aggregator = nil
        mockSettings = nil
        super.tearDown()
    }

    // MARK: - Unavailable Battery

    func testRefresh_noBattery_showsUnavailable() {
        mockBattery.stubbedBatteryState = nil

        vm.refresh(currentMetrics: TestData.sampleMetrics())

        XCTAssertEqual(vm.batteryText, "Battery: Unavailable")
        XCTAssertTrue(vm.isVisible)
    }

    // MARK: - On Battery Power

    func testRefresh_onBattery_withTime() {
        let battery = TestData.batteryOnBattery(capacity: 5000, voltage: 12000) // 60Wh
        mockBattery.stubbedBatteryState = battery
        mockBattery.stubbedRemainingTime = 14400 // 4 hours

        let metrics = TestData.metrics(sysPower: 15.0)
        vm.refresh(currentMetrics: metrics)

        XCTAssertTrue(vm.batteryText.contains("4h 00m remaining"))
        XCTAssertTrue(vm.batteryText.contains("60.0Wh"))
        XCTAssertFalse(vm.batteryText.contains("charging"))
    }

    func testRefresh_charging_withTime() {
        let battery = TestData.batteryCharging(capacity: 5000, voltage: 12800)
        mockBattery.stubbedBatteryState = battery
        mockBattery.stubbedRemainingTime = 3600

        let metrics = TestData.metrics(sysPower: 15.0)
        vm.refresh(currentMetrics: metrics)

        XCTAssertTrue(vm.batteryText.contains("charging"))
    }

    func testRefresh_passesCorrectPowerToCalculation() {
        let battery = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        mockBattery.stubbedBatteryState = battery
        mockBattery.stubbedRemainingTime = 7200

        let metrics = TestData.metrics(sysPower: 15.0)
        vm.refresh(currentMetrics: metrics)

        // Verify the mock was called with correct args
        XCTAssertEqual(mockBattery.calculateRemainingTimeCallCount, 1)
        XCTAssertNotNil(mockBattery.lastCalculateArgs)
        XCTAssertEqual(mockBattery.lastCalculateArgs?.battery, battery)
        XCTAssertEqual(mockBattery.lastCalculateArgs!.power, 15.0, accuracy: 0.001)
    }

    func testRefresh_batteryBecomesNilMidSession() {
        // First: battery available
        mockBattery.stubbedBatteryState = TestData.batteryOnBattery()
        mockBattery.stubbedRemainingTime = 3600
        vm.refresh(currentMetrics: TestData.sampleMetrics())
        XCTAssertTrue(vm.batteryText.contains("remaining"))

        // Then: battery removed (desktop Mac)
        mockBattery.stubbedBatteryState = nil
        vm.refresh(currentMetrics: TestData.sampleMetrics())
        XCTAssertEqual(vm.batteryText, "Battery: Unavailable")
    }

    func testRefresh_noPowerValue_showsCalculating() {
        mockBattery.stubbedBatteryState = TestData.batteryOnBattery()
        // No aggregator data, no instant metrics
        vm.refresh(currentMetrics: nil)

        XCTAssertEqual(vm.batteryText, "Battery: Calculating...")
    }

    func testRefresh_noRemainingTime_showsEnergyOnly() {
        let battery = TestData.batteryOnBattery(capacity: 5000, voltage: 12000)
        mockBattery.stubbedBatteryState = battery
        mockBattery.stubbedRemainingTime = nil

        let metrics = TestData.metrics(sysPower: 15.0)
        vm.refresh(currentMetrics: metrics)

        XCTAssertTrue(vm.batteryText.contains("60.0Wh"))
        XCTAssertTrue(vm.batteryText.contains("remaining"))
        // Should NOT contain formatted time like "4h 00m"
        XCTAssertFalse(vm.batteryText.contains("h 0"))
    }

    // MARK: - Visibility

    func testRefresh_alwaysVisible() {
        mockBattery.stubbedBatteryState = TestData.batteryOnBattery()
        mockBattery.stubbedRemainingTime = 3600

        vm.refresh(currentMetrics: TestData.sampleMetrics())

        XCTAssertTrue(vm.isVisible)
    }
}
