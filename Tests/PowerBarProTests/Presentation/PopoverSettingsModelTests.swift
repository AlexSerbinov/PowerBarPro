import XCTest
import Combine
@testable import PowerBarPro

final class PopoverSettingsModelTests: XCTestCase {

    private var settings: MockSettingsStore!
    private var model: PopoverSettingsModel!

    override func setUp() {
        super.setUp()
        settings = MockSettingsStore()
        model = PopoverSettingsModel(settings: settings)
    }

    override func tearDown() {
        model = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInit_readsCurrentSettings() {
        XCTAssertEqual(model.displayModeSeconds, 3)          // default .average(3)
        XCTAssertEqual(model.batteryModeSeconds, 300)        // default .average(300)
        XCTAssertEqual(model.updateIntervalMs, 1000)
        XCTAssertEqual(model.processAveragingSeconds, 30)
    }

    func testInit_instantModeMapsToZero() {
        settings.displayMode = .instant
        let m = PopoverSettingsModel(settings: settings)
        XCTAssertEqual(m.displayModeSeconds, 0)
    }

    // MARK: - Model → storage

    func testSettingIntervalOnModel_writesToStorage() {
        model.updateIntervalMs = 250
        XCTAssertEqual(settings.updateIntervalMs, 250)
    }

    func testSettingDisplaySecondsOnModel_writesModeToStorage() {
        model.displayModeSeconds = 60
        XCTAssertEqual(settings.displayMode, .average(seconds: 60))

        model.displayModeSeconds = 0
        XCTAssertEqual(settings.displayMode, .instant)
    }

    func testSettingBatterySecondsOnModel_writesModeToStorage() {
        model.batteryModeSeconds = 1800
        XCTAssertEqual(settings.batteryDisplayMode, .average(seconds: 1800))
    }

    func testSettingProcessAveragingOnModel_writesToStorage() {
        model.processAveragingSeconds = 60
        XCTAssertEqual(settings.processAveragingSeconds, 60)
    }

    // MARK: - Storage → model (the "shows 1s after picking 250ms" bug)

    func testStorageIntervalChange_updatesModel() {
        settings.updateIntervalMs = 250

        let exp = expectation(description: "model updated")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(model.updateIntervalMs, 250)
    }

    func testStorageDisplayModeChange_updatesModel() {
        settings.displayMode = .average(seconds: 600)

        let exp = expectation(description: "model updated")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(model.displayModeSeconds, 600)
    }

    func testRoundTrip_doesNotPingPong() {
        var storageWrites = 0
        var cancellables = Set<AnyCancellable>()
        settings.updateIntervalMsPublisher
            .dropFirst()
            .sink { _ in storageWrites += 1 }
            .store(in: &cancellables)

        model.updateIntervalMs = 500

        let exp = expectation(description: "settle")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        XCTAssertEqual(settings.updateIntervalMs, 500)
        XCTAssertEqual(model.updateIntervalMs, 500)
        XCTAssertEqual(storageWrites, 1, "echo from storage must not re-write storage")
    }
}

// MARK: - Chart downsampling

final class SparklineDownsampleTests: XCTestCase {

    private func readings(_ values: [Double]) -> [PowerReading] {
        let base = Date(timeIntervalSince1970: 1_000_000)
        return values.enumerated().map { i, v in
            PowerReading(allPower: v, sysPower: v, timestamp: base.addingTimeInterval(Double(i)))
        }
    }

    func testDownsample_smallInputUnchanged() {
        let input = readings([1, 2, 3])
        let out = SparklineChartView.downsample(input, to: 10)
        XCTAssertEqual(out.count, 3)
    }

    func testDownsample_reducesToTargetCount() {
        let input = readings((0..<1000).map(Double.init))
        let out = SparklineChartView.downsample(input, to: 180)
        XCTAssertEqual(out.count, 180)
    }

    func testDownsample_preservesAverage() {
        let input = readings((0..<600).map { _ in 10.0 })
        let out = SparklineChartView.downsample(input, to: 100)
        XCTAssertTrue(out.allSatisfy { abs($0.sysPower - 10.0) < 0.0001 })
    }

    func testDownsample_timestampsAreMonotonic() {
        let input = readings((0..<500).map(Double.init))
        let out = SparklineChartView.downsample(input, to: 60)
        let stamps = out.map(\.timestamp)
        XCTAssertEqual(stamps, stamps.sorted())
    }
}
