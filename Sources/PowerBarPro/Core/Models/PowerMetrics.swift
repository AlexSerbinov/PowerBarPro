import Foundation

/// Raw power metrics from macmon JSON output.
/// Maps snake_case JSON keys to Swift camelCase properties.
struct PowerMetrics: Codable, Equatable, Sendable {
    let allPower: Double
    let anePower: Double
    let cpuPower: Double
    let ecpuUsage: [Double]
    let gpuPower: Double
    let gpuRamPower: Double
    let gpuUsage: [Double]
    let memory: MemoryMetrics
    let pcpuUsage: [Double]
    let ramPower: Double
    let sysPower: Double
    let temp: TemperatureMetrics
    let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case allPower = "all_power"
        case anePower = "ane_power"
        case cpuPower = "cpu_power"
        case ecpuUsage = "ecpu_usage"
        case gpuPower = "gpu_power"
        case gpuRamPower = "gpu_ram_power"
        case gpuUsage = "gpu_usage"
        case memory
        case pcpuUsage = "pcpu_usage"
        case ramPower = "ram_power"
        case sysPower = "sys_power"
        case temp
        case timestamp
    }
}

/// RAM and swap usage metrics.
struct MemoryMetrics: Codable, Equatable, Sendable {
    let ramTotal: Int64
    let ramUsage: Int64
    let swapTotal: Int64
    let swapUsage: Int64

    private enum CodingKeys: String, CodingKey {
        case ramTotal = "ram_total"
        case ramUsage = "ram_usage"
        case swapTotal = "swap_total"
        case swapUsage = "swap_usage"
    }
}

/// CPU and GPU temperature averages.
struct TemperatureMetrics: Codable, Equatable, Sendable {
    let cpuTempAvg: Double
    let gpuTempAvg: Double

    private enum CodingKeys: String, CodingKey {
        case cpuTempAvg = "cpu_temp_avg"
        case gpuTempAvg = "gpu_temp_avg"
    }
}
