import XCTest
@testable import PowerBarPro

final class PowerReadingTests: XCTestCase {

    func testCreation_defaultTimestamp() {
        let before = Date()
        let reading = PowerReading(allPower: 18.5, sysPower: 12.1)
        let after = Date()

        XCTAssertEqual(reading.allPower, 18.5, accuracy: 0.001)
        XCTAssertEqual(reading.sysPower, 12.1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(reading.timestamp, before)
        XCTAssertLessThanOrEqual(reading.timestamp, after)
    }

    func testCreation_customTimestamp() {
        let date = Date(timeIntervalSince1970: 1000000)
        let reading = PowerReading(allPower: 10, sysPower: 8, timestamp: date)

        XCTAssertEqual(reading.timestamp, date)
    }

    func testCreation_customID() {
        let id = UUID()
        let reading = PowerReading(allPower: 10, sysPower: 8, id: id)

        XCTAssertEqual(reading.id, id)
    }

    func testUniqueIDs() {
        let r1 = PowerReading(allPower: 10, sysPower: 8)
        let r2 = PowerReading(allPower: 10, sysPower: 8)

        XCTAssertNotEqual(r1.id, r2.id)
    }

    func testZeroPower() {
        let reading = PowerReading(allPower: 0, sysPower: 0)
        XCTAssertEqual(reading.allPower, 0)
        XCTAssertEqual(reading.sysPower, 0)
    }

    func testHighPower() {
        let reading = PowerReading(allPower: 150, sysPower: 120)
        XCTAssertEqual(reading.allPower, 150)
        XCTAssertEqual(reading.sysPower, 120)
    }

    // MARK: - Identifiable conformance

    func testIdentifiable_hasID() {
        let reading = PowerReading(allPower: 10, sysPower: 8)
        // Identifiable requires 'id' property — compiler enforces this,
        // but let's verify it's a UUID
        XCTAssertFalse(reading.id.uuidString.isEmpty)
    }
}
