import Foundation

// MARK: - Top-level macpow JSON model

/// Comprehensive system metrics from macpow JSON output.
/// This replaces the old `PowerMetrics` model and covers all macpow data.
struct SystemMetrics: Codable, Equatable, Sendable {

    let soc: SoCMetrics
    let battery: BatteryMetrics?
    let adapter: AdapterMetrics?
    let display: DisplayMetrics?
    let keyboard: KeyboardMetrics?
    let audio: AudioMetrics?
    let topProcesses: [ProcessMetrics]
    let temperatures: [TemperatureSensor]
    let fans: [FanMetrics]

    let sysPowerW: Double
    let backlightPowerW: Double
    let ssdPowerW: Double
    let wifiPowerW: Double
    let bluetoothPowerW: Double
    let adapterPowerW: Double?

    let gpuCores: Int?
    let dramGb: Int?
    let memUsedGb: Double?
    let cpuUsagePct: [Double]?
    let ssdModel: String?

    private enum CodingKeys: String, CodingKey {
        case soc
        case battery
        case adapter
        case display
        case keyboard
        case audio
        case topProcesses = "top_processes"
        case temperatures
        case fans
        case sysPowerW = "sys_power_w"
        case backlightPowerW = "backlight_power_w"
        case ssdPowerW = "ssd_power_w"
        case wifiPowerW = "wifi_power_w"
        case bluetoothPowerW = "bluetooth_power_w"
        case adapterPowerW = "adapter_power_w"
        case gpuCores = "gpu_cores"
        case dramGb = "dram_gb"
        case memUsedGb = "mem_used_gb"
        case cpuUsagePct = "cpu_usage_pct"
        case ssdModel = "ssd_model"
    }

    // MARK: - Legacy compatibility (used by PowerAggregator, Formatters, etc.)

    /// Total system power — equivalent to old `sysPower`.
    var sysPower: Double { sysPowerW }

    /// SoC total power — equivalent to old `allPower`.
    var allPower: Double { soc.totalW }

    /// CPU power from SoC.
    var cpuPower: Double { soc.cpuW }

    /// GPU power from SoC.
    var gpuPower: Double { soc.gpuW }

    /// ANE power from SoC.
    var anePower: Double { soc.aneW }

    /// DRAM power from SoC.
    var ramPower: Double { soc.dramW }
}

// MARK: - SoC Metrics

struct SoCMetrics: Codable, Equatable, Sendable {
    let cpuW: Double
    let ecpuClusters: [CPUCluster]
    let pcpuCluster: CPUCluster?
    let gpuW: Double
    let gpuUtilRenderer: Int?
    let gpuUtilDevice: Int?
    let aneW: Double
    let dramW: Double
    let gpuSramW: Double
    let ispW: Double?
    let fabricW: Double
    let mediaW: Double?
    let pcieW: Double?
    let totalW: Double
    let ecpuFreqMhz: Int?
    let pcpuFreqMhz: Int?
    let gpuFreqMhz: Int?

    private enum CodingKeys: String, CodingKey {
        case cpuW = "cpu_w"
        case ecpuClusters = "ecpu_clusters"
        case pcpuCluster = "pcpu_cluster"
        case gpuW = "gpu_w"
        case gpuUtilRenderer = "gpu_util_renderer"
        case gpuUtilDevice = "gpu_util_device"
        case aneW = "ane_w"
        case dramW = "dram_w"
        case gpuSramW = "gpu_sram_w"
        case ispW = "isp_w"
        case fabricW = "fabric_w"
        case mediaW = "media_w"
        case pcieW = "pcie_w"
        case totalW = "total_w"
        case ecpuFreqMhz = "ecpu_freq_mhz"
        case pcpuFreqMhz = "pcpu_freq_mhz"
        case gpuFreqMhz = "gpu_freq_mhz"
    }
}

struct CPUCluster: Codable, Equatable, Sendable {
    let name: String
    let totalW: Double
    let cores: [CPUCore]

    private enum CodingKeys: String, CodingKey {
        case name
        case totalW = "total_w"
        case cores
    }
}

struct CPUCore: Codable, Equatable, Sendable {
    let name: String
    let watts: Double
}

// MARK: - Battery Metrics

struct BatteryMetrics: Codable, Equatable, Sendable {
    let present: Bool
    let charging: Bool
    let voltageMv: Double?
    let amperageMa: Double?
    let drainW: Double?
    let capacityWh: Double?
    let currentCapacity: Int?
    let maxCapacity: Int?
    let percent: Double
    let timeRemainingMin: Int?
    let externalConnected: Bool
    let temperatureC: Double?
    let cycleCount: Int?
    let designCapacityMah: Double?
    let maxCapacityMah: Double?
    let healthPct: Double?

    private enum CodingKeys: String, CodingKey {
        case present
        case charging
        case voltageMv = "voltage_mv"
        case amperageMa = "amperage_ma"
        case drainW = "drain_w"
        case capacityWh = "capacity_wh"
        case currentCapacity = "current_capacity"
        case maxCapacity = "max_capacity"
        case percent
        case timeRemainingMin = "time_remaining_min"
        case externalConnected = "external_connected"
        case temperatureC = "temperature_c"
        case cycleCount = "cycle_count"
        case designCapacityMah = "design_capacity_mah"
        case maxCapacityMah = "max_capacity_mah"
        case healthPct = "health_pct"
    }
}

// MARK: - Adapter Metrics

struct AdapterMetrics: Codable, Equatable, Sendable {
    let connected: Bool
    let watts: Int?
    let voltageMv: Int?
    let currentMa: Int?
    let isWireless: Bool?

    private enum CodingKeys: String, CodingKey {
        case connected
        case watts
        case voltageMv = "voltage_mv"
        case currentMa = "current_ma"
        case isWireless = "is_wireless"
    }
}

// MARK: - Display Metrics

struct DisplayMetrics: Codable, Equatable, Sendable {
    let brightnessPct: Double
    let nits: Double
    let maxNits: Double?
    let estimatedPowerW: Double
    let available: Bool
    let widthPx: Int?
    let heightPx: Int?

    private enum CodingKeys: String, CodingKey {
        case brightnessPct = "brightness_pct"
        case nits
        case maxNits = "max_nits"
        case estimatedPowerW = "estimated_power_w"
        case available
        case widthPx = "width_px"
        case heightPx = "height_px"
    }
}

// MARK: - Keyboard & Audio

struct KeyboardMetrics: Codable, Equatable, Sendable {
    let brightnessPct: Double?
    let estimatedPowerW: Double?

    private enum CodingKeys: String, CodingKey {
        case brightnessPct = "brightness_pct"
        case estimatedPowerW = "estimated_power_w"
    }
}

struct AudioMetrics: Codable, Equatable, Sendable {
    let volumePct: Double?
    let muted: Bool?
    let playing: Bool?
    let estimatedPowerW: Double?

    private enum CodingKeys: String, CodingKey {
        case volumePct = "volume_pct"
        case muted
        case playing
        case estimatedPowerW = "estimated_power_w"
    }
}

// MARK: - Per-Process Metrics (from macpow)

struct ProcessMetrics: Codable, Equatable, Sendable {
    let pid: Int
    let name: String
    let powerW: Double?
    let energyMj: Double?
    let physMemBytes: UInt64?

    private enum CodingKeys: String, CodingKey {
        case pid
        case name
        case powerW = "power_w"
        case energyMj = "energy_mj"
        case physMemBytes = "phys_mem_bytes"
    }
}

// MARK: - Temperature & Fan

struct TemperatureSensor: Codable, Equatable, Sendable {
    let key: String
    let category: String?
    let valueCelsius: Double

    private enum CodingKeys: String, CodingKey {
        case key
        case category
        case valueCelsius = "value_celsius"
    }
}

struct FanMetrics: Codable, Equatable, Sendable {
    let id: Int?
    let name: String
    let actualRpm: Double
    let minRpm: Double?
    let maxRpm: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case actualRpm = "actual_rpm"
        case minRpm = "min_rpm"
        case maxRpm = "max_rpm"
    }
}
