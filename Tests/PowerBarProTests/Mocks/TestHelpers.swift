import Foundation
@testable import PowerBarPro

/// Shared test data builders for PowerBarPro tests.
enum TestData {

    /// Realistic macpow JSON matching what the actual subprocess outputs.
    static let sampleJSON = """
    {
        "soc": {
            "cpu_w": 3.2,
            "ecpu_clusters": [],
            "pcpu_cluster": {"name": "PCPU", "total_w": 3.0, "cores": []},
            "gpu_w": 1.8,
            "gpu_util_renderer": 5,
            "gpu_util_device": 3,
            "ane_w": 0.0,
            "ane_parts": [],
            "dram_w": 0.8,
            "gpu_sram_w": 0.002,
            "isp_w": 0.004,
            "display_soc_w": 0.0,
            "display_ext_w": 0.0,
            "pcie_w": 0.0,
            "media_w": 0.008,
            "fabric_w": 2.43,
            "total_w": 18.5,
            "ecpu_freq_mhz": 2064,
            "pcpu_freq_mhz": 3153,
            "gpu_freq_mhz": 408
        },
        "battery": {
            "present": true,
            "charging": false,
            "voltage_mv": 12000,
            "amperage_ma": -1250,
            "drain_w": 15.0,
            "capacity_wh": 60.0,
            "current_capacity": 80,
            "max_capacity": 100,
            "percent": 80.0,
            "time_remaining_min": 240,
            "external_connected": false,
            "temperature_c": 35.0,
            "cycle_count": 403,
            "design_capacity_mah": 6075,
            "max_capacity_mah": 4970,
            "health_pct": 81.8
        },
        "display": {
            "brightness_pct": 75.0,
            "nits": 375.0,
            "max_nits": 500.0,
            "estimated_power_w": 1.26,
            "available": true,
            "width_px": 1800,
            "height_px": 1169
        },
        "top_processes": [
            {"pid": 1234, "name": "Safari", "power_w": 0.5, "energy_mj": 100.0, "phys_mem_bytes": 524288000},
            {"pid": 5678, "name": "Terminal", "power_w": 0.1, "energy_mj": 20.0, "phys_mem_bytes": 52428800}
        ],
        "temperatures": [
            {"key": "Tp09", "category": "CPU", "value_celsius": 52.3},
            {"key": "Tg0p", "category": "GPU", "value_celsius": 48.1}
        ],
        "fans": [
            {"id": 0, "name": "Fan 0", "actual_rpm": 1200.0, "min_rpm": 1200.0, "max_rpm": 5779.0}
        ],
        "sys_power_w": 12.1,
        "backlight_power_w": 4.5,
        "ssd_power_w": 0.12,
        "wifi_power_w": 0.05,
        "bluetooth_power_w": 0.01,
        "adapter_power_w": 0.0,
        "gpu_cores": 14,
        "dram_gb": 16,
        "mem_used_gb": 12.5,
        "cpu_usage_pct": [45.2, 32.1],
        "ssd_model": "APPLE SSD AP0512R"
    }
    """

    /// Decode the sample JSON into SystemMetrics.
    static func sampleMetrics() -> SystemMetrics {
        let data = sampleJSON.data(using: .utf8)!
        return try! JSONDecoder().decode(SystemMetrics.self, from: data)
    }

    /// Build SystemMetrics with custom sys/all power values.
    static func metrics(sysPower: Double, allPower: Double = 0) -> SystemMetrics {
        let json = """
        {
            "soc": {
                "cpu_w": 0.0, "ecpu_clusters": [],
                "pcpu_cluster": {"name": "", "total_w": 0.0, "cores": []},
                "gpu_w": 0.0, "ane_w": 0.0, "dram_w": 0.0,
                "gpu_sram_w": 0.0, "fabric_w": 0.0, "total_w": \(allPower)
            },
            "top_processes": [],
            "temperatures": [],
            "fans": [],
            "sys_power_w": \(sysPower),
            "backlight_power_w": 0.0,
            "ssd_power_w": 0.0,
            "wifi_power_w": 0.0,
            "bluetooth_power_w": 0.0
        }
        """
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(SystemMetrics.self, from: data)
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
