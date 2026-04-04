import XCTest
@testable import PowerBarPro

final class PowerAggregatorTests: XCTestCase {

    var aggregator: PowerAggregator!

    override func setUp() {
        super.setUp()
        aggregator = PowerAggregator(maxHistoryDuration: 3600) // 1 hour for tests
    }

    override func tearDown() {
        aggregator = nil
        super.tearDown()
    }

    // MARK: - record & readingCount

    func testInitialState_empty() {
        XCTAssertEqual(aggregator.readingCount, 0)
    }

    func testRecord_incrementsCount() {
        aggregator.record(PowerReading(allPower: 10, sysPower: 8))
        XCTAssertEqual(aggregator.readingCount, 1)

        aggregator.record(PowerReading(allPower: 12, sysPower: 9))
        XCTAssertEqual(aggregator.readingCount, 2)
    }

    func testReset_clearsAll() {
        aggregator.record(PowerReading(allPower: 10, sysPower: 8))
        aggregator.record(PowerReading(allPower: 12, sysPower: 9))
        aggregator.reset()
        XCTAssertEqual(aggregator.readingCount, 0)
    }

    // MARK: - readings(for:)

    func testReadings_allTime_returnsAll() {
        aggregator.record(PowerReading(allPower: 10, sysPower: 8))
        aggregator.record(PowerReading(allPower: 12, sysPower: 9))

        let readings = aggregator.readings(for: 0)
        XCTAssertEqual(readings.count, 2)
    }

    func testReadings_recentOnly() {
        // Add an old reading (2 minutes ago)
        let oldReading = PowerReading(
            allPower: 10, sysPower: 8,
            timestamp: Date().addingTimeInterval(-120)
        )
        aggregator.record(oldReading)

        // Add a fresh reading
        aggregator.record(PowerReading(allPower: 15, sysPower: 12))

        // 60-second window should only include the fresh one
        let recent = aggregator.readings(for: 60)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first!.sysPower, 12.0, accuracy: 0.001)
    }

    func testReadings_emptyHistory() {
        let readings = aggregator.readings(for: 60)
        XCTAssertTrue(readings.isEmpty)
    }

    // MARK: - average(for:)

    func testAverage_singleReading() {
        aggregator.record(PowerReading(allPower: 20, sysPower: 15))

        let avg = aggregator.average(for: 0)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!.sysPower, 15.0, accuracy: 0.001)
        XCTAssertEqual(avg!.allPower, 20.0, accuracy: 0.001)
    }

    func testAverage_multipleReadings() {
        aggregator.record(PowerReading(allPower: 20, sysPower: 10))
        aggregator.record(PowerReading(allPower: 30, sysPower: 20))
        aggregator.record(PowerReading(allPower: 10, sysPower: 15))

        let avg = aggregator.average(for: 0)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!.sysPower, 15.0, accuracy: 0.001) // (10+20+15)/3
        XCTAssertEqual(avg!.allPower, 20.0, accuracy: 0.001) // (20+30+10)/3
    }

    func testAverage_noData_returnsNil() {
        let avg = aggregator.average(for: 60)
        XCTAssertNil(avg)
    }

    func testAverage_windowExcludesOld() {
        // Old reading: 100W, 2 minutes ago
        aggregator.record(PowerReading(
            allPower: 100, sysPower: 100,
            timestamp: Date().addingTimeInterval(-120)
        ))
        // New reading: 10W, now
        aggregator.record(PowerReading(allPower: 10, sysPower: 10))

        // 30-second average should only include the new reading
        let avg = aggregator.average(for: 30)
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!.sysPower, 10.0, accuracy: 0.001)
    }

    // MARK: - resolvedPower(for:instant:)

    func testResolvedPower_instant_returnsCurrentSysPower() {
        let metrics = TestData.metrics(sysPower: 12.5)
        let resolved = aggregator.resolvedPower(for: .instant, instant: metrics)
        XCTAssertEqual(resolved!, 12.5, accuracy: 0.001)
    }

    func testResolvedPower_average_withData() {
        aggregator.record(PowerReading(allPower: 20, sysPower: 15))
        aggregator.record(PowerReading(allPower: 30, sysPower: 25))

        let metrics = TestData.metrics(sysPower: 50) // instant is 50
        let resolved = aggregator.resolvedPower(for: .average(seconds: 0), instant: metrics)

        // Should return average (20), not instant (50)
        XCTAssertEqual(resolved!, 20.0, accuracy: 0.001)
    }

    func testResolvedPower_average_noData_fallsBackToInstant() {
        let metrics = TestData.metrics(sysPower: 42)
        let resolved = aggregator.resolvedPower(for: .average(seconds: 60), instant: metrics)

        // No averaging data → fallback to instant
        XCTAssertEqual(resolved!, 42.0, accuracy: 0.001)
    }

    func testResolvedPower_nilMetrics_returnsNil() {
        let resolved = aggregator.resolvedPower(for: .instant, instant: nil)
        XCTAssertNil(resolved)
    }

    // MARK: - History pruning

    func testPruning_removesOldReadings() {
        // Create aggregator with short max duration
        let shortAggregator = PowerAggregator(maxHistoryDuration: 5) // 5 seconds

        // Add an old reading (10 seconds ago)
        shortAggregator.record(PowerReading(
            allPower: 100, sysPower: 100,
            timestamp: Date().addingTimeInterval(-10)
        ))

        // Add a new reading — this triggers pruning
        shortAggregator.record(PowerReading(allPower: 10, sysPower: 10))

        // Old reading should be pruned
        XCTAssertEqual(shortAggregator.readingCount, 1)
        XCTAssertEqual(shortAggregator.readings(for: 0).first!.sysPower, 10.0, accuracy: 0.001)
    }
}
