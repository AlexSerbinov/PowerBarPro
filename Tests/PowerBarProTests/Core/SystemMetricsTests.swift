import XCTest
@testable import PowerBarPro

final class SystemMetricsTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecoding_validJSON() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.sysPowerW, 12.1, accuracy: 0.001)
        XCTAssertEqual(metrics.backlightPowerW, 4.5, accuracy: 0.001)
        XCTAssertEqual(metrics.ssdPowerW, 0.12, accuracy: 0.001)
        XCTAssertEqual(metrics.wifiPowerW, 0.05, accuracy: 0.001)
        XCTAssertEqual(metrics.bluetoothPowerW, 0.01, accuracy: 0.001)
    }

    func testDecoding_socMetrics() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.soc.cpuW, 3.2, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.gpuW, 1.8, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.aneW, 0.0, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.dramW, 0.8, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.totalW, 18.5, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.fabricW, 2.43, accuracy: 0.001)
    }

    func testDecoding_battery() throws {
        let metrics = TestData.sampleMetrics()
        let battery = metrics.battery

        XCTAssertNotNil(battery)
        XCTAssertTrue(battery!.present)
        XCTAssertFalse(battery!.charging)
        XCTAssertEqual(battery!.percent, 80.0, accuracy: 0.001)
        XCTAssertEqual(battery!.healthPct!, 81.8, accuracy: 0.1)
        XCTAssertEqual(battery!.cycleCount, 403)
    }

    func testDecoding_display() throws {
        let metrics = TestData.sampleMetrics()
        let display = metrics.display

        XCTAssertNotNil(display)
        XCTAssertTrue(display!.available)
        XCTAssertEqual(display!.brightnessPct, 75.0, accuracy: 0.001)
        XCTAssertEqual(display!.nits, 375.0, accuracy: 0.001)
        XCTAssertEqual(display!.estimatedPowerW, 1.26, accuracy: 0.01)
    }

    func testDecoding_processes() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.topProcesses.count, 2)
        XCTAssertEqual(metrics.topProcesses[0].name, "Safari")
        XCTAssertEqual(metrics.topProcesses[0].powerW!, 0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.topProcesses[1].name, "Terminal")
    }

    func testDecoding_temperatures() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.temperatures.count, 2)
        XCTAssertEqual(metrics.temperatures[0].category, "CPU")
        XCTAssertEqual(metrics.temperatures[0].valueCelsius, 52.3, accuracy: 0.001)
    }

    func testDecoding_fans() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.fans.count, 1)
        XCTAssertEqual(metrics.fans[0].actualRpm, 1200, accuracy: 0.1)
    }

    func testDecoding_systemInfo() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.gpuCores, 14)
        XCTAssertEqual(metrics.dramGb, 16)
        XCTAssertEqual(metrics.memUsedGb!, 12.5, accuracy: 0.1)
        XCTAssertEqual(metrics.cpuUsagePct?.count, 2)
    }

    // MARK: - Legacy compatibility properties

    func testLegacyCompat_sysPower() {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.sysPower, metrics.sysPowerW)
    }

    func testLegacyCompat_allPower() {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.allPower, metrics.soc.totalW)
    }

    func testLegacyCompat_cpuPower() {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.cpuPower, metrics.soc.cpuW)
    }

    func testLegacyCompat_gpuPower() {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.gpuPower, metrics.soc.gpuW)
    }

    func testLegacyCompat_ramPower() {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.ramPower, metrics.soc.dramW)
    }

    // MARK: - Minimal JSON (no optional fields)

    func testDecoding_minimalJSON() throws {
        let metrics = TestData.metrics(sysPower: 5.0, allPower: 3.0)

        XCTAssertEqual(metrics.sysPowerW, 5.0, accuracy: 0.001)
        XCTAssertEqual(metrics.soc.totalW, 3.0, accuracy: 0.001)
        XCTAssertNil(metrics.battery)
        XCTAssertNil(metrics.display)
        XCTAssertTrue(metrics.topProcesses.isEmpty)
        XCTAssertTrue(metrics.temperatures.isEmpty)
    }

    // MARK: - Equatable

    func testEquatable_sameValues() {
        let a = TestData.metrics(sysPower: 10.0)
        let b = TestData.metrics(sysPower: 10.0)
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentValues() {
        let a = TestData.metrics(sysPower: 10.0)
        let b = TestData.metrics(sysPower: 20.0)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Invalid JSON

    func testDecoding_invalidJSON_throws() {
        let data = "{ not valid }".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SystemMetrics.self, from: data))
    }
}
