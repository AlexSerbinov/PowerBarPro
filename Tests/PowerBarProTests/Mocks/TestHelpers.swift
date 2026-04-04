import Foundation
@testable import PowerBarPro

/// Shared test data builders for PowerBarPro tests.
enum TestData {

    /// Realistic macmon JSON matching what the actual subprocess outputs.
    static let sampleJSON = """
    {
        "all_power": 18.5,
        "ane_power": 0.0,
        "cpu_power": 3.2,
        "ecpu_usage": [12.5, 8.3, 15.1, 9.7],
        "gpu_power": 1.8,
        "gpu_ram_power": 0.3,
        "gpu_usage": [5.2, 3.1],
        "memory": {
            "ram_total": 17179869184,
            "ram_usage": 12884901888,
            "swap_total": 4294967296,
            "swap_usage": 1073741824
        },
        "pcpu_usage": [45.2, 32.1, 28.7, 51.3, 22.4, 18.9],
        "ram_power": 0.8,
        "sys_power": 12.1,
        "temp": {
            "cpu_temp_avg": 52.3,
            "gpu_temp_avg": 48.1
        },
        "timestamp": "2025-06-18T14:30:00Z"
    }
    """

    /// Decode the sample JSON into PowerMetrics.
    static func sampleMetrics() -> PowerMetrics {
        let data = sampleJSON.data(using: .utf8)!
        return try! JSONDecoder().decode(PowerMetrics.self, from: data)
    }

    /// Build PowerMetrics with custom sys/all power values.
    static func metrics(sysPower: Double, allPower: Double = 0) -> PowerMetrics {
        let json = """
        {
            "all_power": \(allPower),
            "ane_power": 0.0,
            "cpu_power": 0.0,
            "ecpu_usage": [],
            "gpu_power": 0.0,
            "gpu_ram_power": 0.0,
            "gpu_usage": [],
            "memory": { "ram_total": 0, "ram_usage": 0, "swap_total": 0, "swap_usage": 0 },
            "pcpu_usage": [],
            "ram_power": 0.0,
            "sys_power": \(sysPower),
            "temp": { "cpu_temp_avg": 0, "gpu_temp_avg": 0 },
            "timestamp": ""
        }
        """
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(PowerMetrics.self, from: data)
    }

    /// Typical MacBook Pro battery on battery power.
    static func batteryOnBattery(capacity: Int = 5000, voltage: Int = 12000) -> BatteryState {
        BatteryState(
            isCharging: false,
            externalConnected: false,
            currentCapacity: capacity,
            voltage: voltage
        )
    }

    /// Battery connected to external power.
    static func batteryCharging(capacity: Int = 5000, voltage: Int = 12800) -> BatteryState {
        BatteryState(
            isCharging: true,
            externalConnected: true,
            currentCapacity: capacity,
            voltage: voltage
        )
    }
}
