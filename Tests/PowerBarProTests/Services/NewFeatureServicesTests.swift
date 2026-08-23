import XCTest
@testable import PowerBarPro

// MARK: - SessionEnergyTracker

final class SessionEnergyTrackerTests: XCTestCase {

    func testIntegratesEnergyOverTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let tracker = SessionEnergyTracker(startedAt: start)

        // 10W for 360 seconds = 1 Wh
        for i in 0...360 {
            tracker.record(watts: 10, at: start.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(tracker.energyWh, 1.0, accuracy: 0.001)
        XCTAssertEqual(tracker.sessionDuration, 360, accuracy: 0.001)
    }

    func testFirstSampleAddsNoEnergy() {
        let tracker = SessionEnergyTracker()
        tracker.record(watts: 100)
        XCTAssertEqual(tracker.energyWh, 0)
    }

    func testLargeGapIsSkipped() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let tracker = SessionEnergyTracker(startedAt: start, maxGapSeconds: 30)

        tracker.record(watts: 10, at: start)
        tracker.record(watts: 10, at: start.addingTimeInterval(1))
        // Sleep/wake gap — must not integrate 2 hours of phantom energy
        tracker.record(watts: 10, at: start.addingTimeInterval(7200))
        XCTAssertEqual(tracker.energyWh, 10.0 / 3600, accuracy: 0.0001)
    }

    func testReset() {
        let tracker = SessionEnergyTracker()
        let t0 = Date()
        tracker.record(watts: 10, at: t0)
        tracker.record(watts: 10, at: t0.addingTimeInterval(10))
        tracker.reset(at: t0.addingTimeInterval(10))
        XCTAssertEqual(tracker.energyWh, 0)
    }
}

// MARK: - PowerAlertService

private final class SpyNotifier: AlertNotifying {
    private(set) var alerts: [(title: String, body: String)] = []
    func postAlert(title: String, body: String) {
        alerts.append((title, body))
    }
}

final class PowerAlertServiceTests: XCTestCase {

    private var notifier: SpyNotifier!
    private var settings: MockSettingsStore!
    private var currentTime: Date!
    private var service: PowerAlertService!

    override func setUp() {
        super.setUp()
        notifier = SpyNotifier()
        settings = MockSettingsStore()
        settings.alertsEnabled = true
        settings.alertThresholdW = 25
        currentTime = Date(timeIntervalSince1970: 1_000_000)
        service = PowerAlertService(
            notifier: notifier,
            settings: settings,
            sustainSeconds: 300,
            cooldownSeconds: 1800,
            now: { self.currentTime }
        )
    }

    private func process(_ name: String, watts: Double) -> AttributedPower {
        AttributedPower(
            id: name, name: name, pids: [1],
            cpuWatts: watts, dramWatts: 0, gpuWatts: 0, storageWatts: 0,
            percentOfSystem: 50, memoryBytes: 0, pidCount: 1, rawCpuWatts: watts
        )
    }

    func testNoAlertBeforeSustainWindow() {
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(299)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertTrue(notifier.alerts.isEmpty)
    }

    func testAlertsAfterSustainedDraw() {
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(301)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertEqual(notifier.alerts.count, 1)
        XCTAssertTrue(notifier.alerts[0].title.contains("Chrome"))
    }

    func testDroppingBelowThresholdResetsStreak() {
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(200)
        service.evaluate([process("Chrome", watts: 5)])   // dip resets
        currentTime = currentTime.addingTimeInterval(150)
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(299)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertTrue(notifier.alerts.isEmpty)
    }

    func testCooldownPreventsRepeatAlerts() {
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(301)
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(60)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertEqual(notifier.alerts.count, 1)

        currentTime = currentTime.addingTimeInterval(1801)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertEqual(notifier.alerts.count, 2)
    }

    func testDisabledSettingsSuppressAlerts() {
        settings.alertsEnabled = false
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(600)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertTrue(notifier.alerts.isEmpty)
    }

    func testThresholdFromSettingsIsRespected() {
        settings.alertThresholdW = 40
        service.evaluate([process("Chrome", watts: 30)])
        currentTime = currentTime.addingTimeInterval(600)
        service.evaluate([process("Chrome", watts: 30)])
        XCTAssertTrue(notifier.alerts.isEmpty)
    }
}

// MARK: - History persistence

final class HistoryPersistenceTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbp-history-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testSaveAndRestoreRoundTrip() {
        let aggregator = PowerAggregator()
        let now = Date()
        for i in 0..<100 {
            aggregator.record(PowerReading(
                allPower: 5, sysPower: 10, timestamp: now.addingTimeInterval(Double(i - 100))
            ))
        }

        let saver = HistoryPersistenceService(aggregator: aggregator, storageURL: tempURL)
        saver.saveNow()

        let fresh = PowerAggregator()
        let loader = HistoryPersistenceService(aggregator: fresh, storageURL: tempURL)
        loader.restore()

        XCTAssertEqual(fresh.readingCount, 100)
        XCTAssertEqual(fresh.average(for: 0)?.sysPower ?? 0, 10, accuracy: 0.001)
    }

    func testRestoreDropsExpiredReadings() {
        let aggregator = PowerAggregator(maxHistoryDuration: 999_999)
        let now = Date()
        aggregator.record(PowerReading(allPower: 1, sysPower: 1, timestamp: now.addingTimeInterval(-30_000)))
        aggregator.record(PowerReading(allPower: 1, sysPower: 1, timestamp: now.addingTimeInterval(-10)))

        let saver = HistoryPersistenceService(aggregator: aggregator, storageURL: tempURL, maxAge: 21600)
        saver.saveNow()

        let fresh = PowerAggregator()
        let loader = HistoryPersistenceService(aggregator: fresh, storageURL: tempURL, maxAge: 21600)
        loader.restore()

        XCTAssertEqual(fresh.readingCount, 1)
    }

    func testRestoreWithMissingFileIsNoop() {
        let fresh = PowerAggregator()
        let loader = HistoryPersistenceService(aggregator: fresh, storageURL: tempURL)
        loader.restore()
        XCTAssertEqual(fresh.readingCount, 0)
    }

    func testAggregatorRestoreKeepsChronologicalOrder() {
        let aggregator = PowerAggregator()
        let now = Date()
        aggregator.record(PowerReading(allPower: 1, sysPower: 1, timestamp: now))
        aggregator.restore([
            PowerReading(allPower: 2, sysPower: 2, timestamp: now.addingTimeInterval(-100)),
            PowerReading(allPower: 3, sysPower: 3, timestamp: now.addingTimeInterval(-50)),
        ])

        let all = aggregator.readings(for: 0)
        let stamps = all.map(\.timestamp)
        XCTAssertEqual(stamps, stamps.sorted())
        XCTAssertEqual(all.count, 3)
    }
}

// MARK: - Fan load bar (menu bar)

final class FanLoadFractionTests: XCTestCase {

    private func fan(_ actual: Double, min: Double? = 0, max: Double? = 6000) -> FanMetrics {
        FanMetrics(id: 0, name: "Fan", actualRpm: actual, minRpm: min, maxRpm: max)
    }

    func testNoFansReturnsNil() {
        XCTAssertNil(MenuBarManager.fanLoadFraction(fans: []))
    }

    func testNormalizesWithinMinMaxRange() {
        let f = MenuBarManager.fanLoadFraction(fans: [fan(3000, min: 0, max: 6000)])
        XCTAssertEqual(f ?? -1, 0.5, accuracy: 0.001)
    }

    func testTakesHighestOfMultipleFans() {
        let f = MenuBarManager.fanLoadFraction(fans: [
            fan(1200, min: 1200, max: 6000),   // idle -> 0
            fan(4800, min: 1200, max: 6000),   // 0.75
        ])
        XCTAssertEqual(f ?? -1, 0.75, accuracy: 0.001)
    }

    func testClampsAboveMaxAndBelowMin() {
        XCTAssertEqual(MenuBarManager.fanLoadFraction(fans: [fan(9000)]) ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(MenuBarManager.fanLoadFraction(fans: [fan(500, min: 1200)]) ?? -1, 0.0, accuracy: 0.001)
    }

    func testInvalidRangeIgnored() {
        XCTAssertNil(MenuBarManager.fanLoadFraction(fans: [fan(3000, min: 0, max: nil)]))
    }

    func testBarColorBands() {
        XCTAssertEqual(MenuBarManager.fanBarColor(0.2), .systemGreen)
        XCTAssertEqual(MenuBarManager.fanBarColor(0.5), .systemBlue)
        XCTAssertEqual(MenuBarManager.fanBarColor(0.9), .systemOrange)
    }

    func testModeTintPalette() {
        XCTAssertEqual(MacFans.modeTint(mode: .auto, pct: 0), .secondaryLabelColor)
        XCTAssertEqual(MacFans.modeTint(mode: .curve, pct: 60), .systemPurple)
        XCTAssertEqual(MacFans.modeTint(mode: .manual, pct: 30), .systemGreen)
        XCTAssertEqual(MacFans.modeTint(mode: .manual, pct: 70), .systemBlue)
        XCTAssertEqual(MacFans.modeTint(mode: .manual, pct: 100), .systemOrange)
    }
}

// MARK: - MacFans client (integration, machine-guarded)

final class MacFansClientTests: XCTestCase {

    /// Read-only round-trip against the live daemon. Skipped on machines
    /// without MacFans installed — never changes fan state.
    func testStatusRoundTrip() throws {
        try XCTSkipUnless(MacFans.daemonInstalled, "macfansd not installed")
        let reply = try MacFans.send(.status)
        XCTAssertTrue(reply.ok)
        XCTAssertFalse(reply.fans.isEmpty)
        XCTAssertGreaterThan(reply.fans[0].max, reply.fans[0].min)
    }

    func testRequestEncoding() throws {
        let data = try JSONEncoder().encode(MacFans.Request.manual(70))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["cmd"] as? String, "set")
        XCTAssertEqual(json["mode"] as? String, "manual")
        XCTAssertEqual(json["pct"] as? Int, 70)
    }
}
