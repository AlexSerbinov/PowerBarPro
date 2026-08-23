import XCTest
@testable import PowerBarPro

final class SystemBatteryServiceTests: XCTestCase {

    var mockRunner: MockProcessRunner!
    var service: SystemBatteryService!

    override func setUp() {
        super.setUp()
        mockRunner = MockProcessRunner()
        service = SystemBatteryService(processRunner: mockRunner)
    }

    override func tearDown() {
        service = nil
        mockRunner = nil
        super.tearDown()
    }

    // MARK: - getBatteryState with mock ioreg data

    func testGetBatteryState_validPlistData() {
        // Simulate ioreg XML plist output
        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>IsCharging</key>
                <false/>
                <key>ExternalConnected</key>
                <false/>
                <key>AppleRawCurrentCapacity</key>
                <integer>5000</integer>
                <key>Voltage</key>
                <integer>12000</integer>
            </dict>
        </array>
        </plist>
        """
        mockRunner.stubbedRunSyncResult = plistXML.data(using: .utf8)

        let state = service.getBatteryState()

        XCTAssertNotNil(state)
        XCTAssertFalse(state!.isCharging)
        XCTAssertFalse(state!.externalConnected)
        XCTAssertEqual(state!.currentCapacity, 5000)
        XCTAssertEqual(state!.voltage, 12000)
    }

    func testGetBatteryState_chargingState() {
        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>IsCharging</key>
                <true/>
                <key>ExternalConnected</key>
                <true/>
                <key>AppleRawCurrentCapacity</key>
                <integer>7200</integer>
                <key>Voltage</key>
                <integer>12800</integer>
            </dict>
        </array>
        </plist>
        """
        mockRunner.stubbedRunSyncResult = plistXML.data(using: .utf8)

        let state = service.getBatteryState()

        XCTAssertNotNil(state)
        XCTAssertTrue(state!.isCharging)
        XCTAssertTrue(state!.externalConnected)
    }

    func testGetBatteryState_processError_returnsNil() {
        mockRunner.stubbedRunSyncError = .processSpawnFailed("ioreg failed")

        let state = service.getBatteryState()
        XCTAssertNil(state)
    }

    func testGetBatteryState_invalidData_returnsNil() {
        mockRunner.stubbedRunSyncResult = "not plist data".data(using: .utf8)

        let state = service.getBatteryState()
        XCTAssertNil(state)
    }

    func testGetBatteryState_zeroCapacity_returnsNil() {
        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>IsCharging</key>
                <false/>
                <key>ExternalConnected</key>
                <false/>
                <key>AppleRawCurrentCapacity</key>
                <integer>0</integer>
                <key>Voltage</key>
                <integer>12000</integer>
            </dict>
        </array>
        </plist>
        """
        mockRunner.stubbedRunSyncResult = plistXML.data(using: .utf8)

        let state = service.getBatteryState()
        XCTAssertNil(state)
    }

    func testGetBatteryState_callsIoreg() {
        mockRunner.stubbedRunSyncResult = Data()
        _ = service.getBatteryState()

        XCTAssertEqual(mockRunner.runSyncCalls.count, 1)
        XCTAssertEqual(mockRunner.runSyncCalls.first?.path, "/usr/sbin/ioreg")
        XCTAssertEqual(mockRunner.runSyncCalls.first?.args, ["-a", "-r", "-n", "AppleSmartBattery"])
    }

    // MARK: - calculateRemainingTime

    func testCalculateRemainingTime_onBattery() {
        let battery = TestData.batteryOnBattery(capacity: 5000, voltage: 12000) // 60Wh
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: 15.0)

        XCTAssertNotNil(time)
        XCTAssertEqual(time!, 14400, accuracy: 1.0) // 60/15 * 3600
    }

    func testCalculateRemainingTime_onExternal_stillEstimates() {
        // On AC the estimate stays available ("how long would it last at
        // this draw") — the UI marks plugged-in state with a bolt instead.
        let battery = TestData.batteryCharging()
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: 15.0)
        XCTAssertNotNil(time)
        XCTAssertGreaterThan(time ?? 0, 0)
    }

    func testCalculateRemainingTime_lowPower_returnsNil() {
        let battery = TestData.batteryOnBattery()
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: 0.05)
        XCTAssertNil(time)
    }

    func testCalculateRemainingTime_exactBoundary_returnsNil() {
        let battery = TestData.batteryOnBattery()
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: 0.1)
        XCTAssertNil(time) // > 0.1, not >= 0.1
    }

    func testCalculateRemainingTime_zeroPower_returnsNil() {
        let battery = TestData.batteryOnBattery()
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: 0.0)
        XCTAssertNil(time)
    }

    func testCalculateRemainingTime_negativePower_returnsNil() {
        let battery = TestData.batteryOnBattery()
        let time = service.calculateRemainingTime(battery: battery, averagePowerW: -5.0)
        XCTAssertNil(time)
    }
}
