import XCTest
@testable import PowerBarPro

final class PowerMetricsTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecoding_validJSON() throws {
        let metrics = TestData.sampleMetrics()

        XCTAssertEqual(metrics.allPower, 18.5, accuracy: 0.001)
        XCTAssertEqual(metrics.anePower, 0.0, accuracy: 0.001)
        XCTAssertEqual(metrics.cpuPower, 3.2, accuracy: 0.001)
        XCTAssertEqual(metrics.gpuPower, 1.8, accuracy: 0.001)
        XCTAssertEqual(metrics.gpuRamPower, 0.3, accuracy: 0.001)
        XCTAssertEqual(metrics.ramPower, 0.8, accuracy: 0.001)
        XCTAssertEqual(metrics.sysPower, 12.1, accuracy: 0.001)
        XCTAssertEqual(metrics.timestamp, "2025-06-18T14:30:00Z")
    }

    func testDecoding_cpuUsageArrays() throws {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.ecpuUsage.count, 4)
        XCTAssertEqual(metrics.pcpuUsage.count, 6)
        XCTAssertEqual(metrics.gpuUsage.count, 2)
    }

    func testDecoding_memoryInfo() throws {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.memory.ramTotal, 17179869184)
        XCTAssertEqual(metrics.memory.ramUsage, 12884901888)
        XCTAssertEqual(metrics.memory.swapTotal, 4294967296)
        XCTAssertEqual(metrics.memory.swapUsage, 1073741824)
    }

    func testDecoding_temperature() throws {
        let metrics = TestData.sampleMetrics()
        XCTAssertEqual(metrics.temp.cpuTempAvg, 52.3, accuracy: 0.001)
        XCTAssertEqual(metrics.temp.gpuTempAvg, 48.1, accuracy: 0.001)
    }

    func testDecoding_invalidJSON_throws() {
        let data = "{ not valid }".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(PowerMetrics.self, from: data))
    }

    func testDecoding_missingField_throws() {
        let json = """
        { "all_power": 1, "ane_power": 0, "cpu_power": 0, "ecpu_usage": [],
          "gpu_power": 0, "gpu_ram_power": 0, "gpu_usage": [],
          "memory": { "ram_total": 0, "ram_usage": 0, "swap_total": 0, "swap_usage": 0 },
          "pcpu_usage": [], "ram_power": 0,
          "temp": { "cpu_temp_avg": 0, "gpu_temp_avg": 0 }, "timestamp": "" }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(PowerMetrics.self, from: data))
    }

    func testDecoding_zeroPower() throws {
        let metrics = TestData.metrics(sysPower: 0.0, allPower: 0.0)
        XCTAssertEqual(metrics.sysPower, 0.0)
        XCTAssertEqual(metrics.allPower, 0.0)
    }

    func testDecoding_highPower() throws {
        let metrics = TestData.metrics(sysPower: 95.7, allPower: 120.3)
        XCTAssertEqual(metrics.sysPower, 95.7, accuracy: 0.001)
        XCTAssertEqual(metrics.allPower, 120.3, accuracy: 0.001)
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
}
