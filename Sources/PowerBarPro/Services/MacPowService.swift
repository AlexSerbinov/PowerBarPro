import Foundation
import Combine

/// Manages the `macpow --json` subprocess for comprehensive power metrics.
/// Replaces MacMonService. Handles multi-line pretty-printed JSON via StreamingJSONParser.
final class MacPowService: PowerMonitoring {

    // MARK: - Published state

    private let metricsSubject = CurrentValueSubject<SystemMetrics?, Never>(nil)
    private let errorSubject = CurrentValueSubject<AppError?, Never>(nil)
    private let isRunningSubject = CurrentValueSubject<Bool, Never>(false)

    var metricsPublisher: AnyPublisher<SystemMetrics?, Never> {
        metricsSubject.eraseToAnyPublisher()
    }
    var errorPublisher: AnyPublisher<AppError?, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    var isRunningPublisher: AnyPublisher<Bool, Never> {
        isRunningSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let processRunner: ProcessRunning
    private var macpowProcess: Process?
    private var updateIntervalMs: Int = Constants.Defaults.updateIntervalMs
    private let decoder = JSONDecoder()
    private let jsonParser = StreamingJSONParser()

    // MARK: - Init

    init(processRunner: ProcessRunning) {
        self.processRunner = processRunner
    }

    // MARK: - PowerMonitoring

    func startMonitoring() {
        guard !isRunningSubject.value else { return }

        guard let macpowPath = processRunner.findExecutable(
            name: Constants.MacPow.binaryName,
            searchPaths: Constants.MacPow.searchPaths
        ) else {
            // Fallback to macmon if macpow not found
            guard let macmonPath = processRunner.findExecutable(
                name: Constants.MacMon.binaryName,
                searchPaths: Constants.MacMon.searchPaths
            ) else {
                errorSubject.send(.macmonNotFound)
                return
            }
            startProcess(path: macmonPath, args: ["pipe", "--interval", "\(updateIntervalMs)"], isLegacy: true)
            return
        }

        startProcess(path: macpowPath, args: ["--json", "--interval", "\(updateIntervalMs)"], isLegacy: false)
    }

    func stopMonitoring() {
        guard isRunningSubject.value else { return }
        macpowProcess?.terminate()
        macpowProcess = nil
        isRunningSubject.send(false)
        metricsSubject.send(nil)
        errorSubject.send(nil)
        jsonParser.reset()
    }

    func setUpdateInterval(_ intervalMs: Int) {
        updateIntervalMs = intervalMs
        if isRunningSubject.value {
            stopMonitoring()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startMonitoring()
            }
        }
    }

    // MARK: - Private

    private func startProcess(path: String, args: [String], isLegacy: Bool) {
        let (process, pipe) = processRunner.createStreamingProcess(
            executablePath: path,
            arguments: args
        )

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunningSubject.send(false)
                if proc.terminationStatus != 0 {
                    self?.errorSubject.send(.macmonTerminated(status: proc.terminationStatus))
                }
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(data: data, encoding: .utf8) ?? ""

            if isLegacy {
                self?.processLegacyOutput(output)
            } else {
                self?.processMacPowOutput(output)
            }
        }

        do {
            try process.run()
            macpowProcess = process
            isRunningSubject.send(true)
            errorSubject.send(nil)
        } catch {
            errorSubject.send(.macmonStartFailed(error.localizedDescription))
        }
    }

    /// Parse macpow multi-line pretty-printed JSON.
    private func processMacPowOutput(_ output: String) {
        let jsonObjects = jsonParser.feed(output)

        for data in jsonObjects {
            do {
                let metrics = try decoder.decode(SystemMetrics.self, from: data)
                DispatchQueue.main.async { [weak self] in
                    self?.metricsSubject.send(metrics)
                }
            } catch {
                // Partial/corrupt JSON — skip silently
            }
        }
    }

    /// Parse legacy macmon single-line JSON (fallback mode).
    private func processLegacyOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            do {
                let legacy = try decoder.decode(LegacyMacMonMetrics.self, from: data)
                let metrics = legacy.toSystemMetrics()
                DispatchQueue.main.async { [weak self] in
                    self?.metricsSubject.send(metrics)
                }
            } catch {
                // Skip partial lines
            }
        }
    }
}

// MARK: - Legacy macmon JSON model (fallback)

/// Maps old macmon JSON format to SystemMetrics for backward compatibility.
private struct LegacyMacMonMetrics: Codable {
    let allPower: Double
    let anePower: Double
    let cpuPower: Double
    let gpuPower: Double
    let gpuRamPower: Double
    let ramPower: Double
    let sysPower: Double
    let ecpuUsage: [Double]?
    let pcpuUsage: [Double]?
    let gpuUsage: [Double]?
    let memory: LegacyMemory?
    let temp: LegacyTemp?

    private enum CodingKeys: String, CodingKey {
        case allPower = "all_power"
        case anePower = "ane_power"
        case cpuPower = "cpu_power"
        case gpuPower = "gpu_power"
        case gpuRamPower = "gpu_ram_power"
        case ramPower = "ram_power"
        case sysPower = "sys_power"
        case ecpuUsage = "ecpu_usage"
        case pcpuUsage = "pcpu_usage"
        case gpuUsage = "gpu_usage"
        case memory
        case temp
    }

    struct LegacyMemory: Codable {
        let ramTotal: Int64?
        let ramUsage: Int64?
        private enum CodingKeys: String, CodingKey {
            case ramTotal = "ram_total"
            case ramUsage = "ram_usage"
        }
    }

    struct LegacyTemp: Codable {
        let cpuTempAvg: Double?
        let gpuTempAvg: Double?
        private enum CodingKeys: String, CodingKey {
            case cpuTempAvg = "cpu_temp_avg"
            case gpuTempAvg = "gpu_temp_avg"
        }
    }

    func toSystemMetrics() -> SystemMetrics {
        let soc = SoCMetrics(
            cpuW: cpuPower,
            ecpuClusters: [],
            pcpuCluster: nil,
            gpuW: gpuPower,
            gpuUtilRenderer: nil,
            gpuUtilDevice: nil,
            aneW: anePower,
            dramW: ramPower,
            gpuSramW: gpuRamPower,
            ispW: nil,
            fabricW: 0,
            mediaW: nil,
            pcieW: nil,
            totalW: allPower,
            ecpuFreqMhz: nil,
            pcpuFreqMhz: nil,
            gpuFreqMhz: nil
        )

        var temps: [TemperatureSensor] = []
        if let t = temp {
            if let cpu = t.cpuTempAvg {
                temps.append(TemperatureSensor(key: "cpu_avg", category: "CPU", valueCelsius: cpu))
            }
            if let gpu = t.gpuTempAvg {
                temps.append(TemperatureSensor(key: "gpu_avg", category: "GPU", valueCelsius: gpu))
            }
        }

        return SystemMetrics(
            soc: soc,
            battery: nil,
            adapter: nil,
            display: nil,
            keyboard: nil,
            audio: nil,
            topProcesses: [],
            temperatures: temps,
            fans: [],
            sysPowerW: sysPower,
            backlightPowerW: 0,
            ssdPowerW: 0,
            wifiPowerW: 0,
            bluetoothPowerW: 0,
            adapterPowerW: nil,
            gpuCores: nil,
            dramGb: nil,
            memUsedGb: memory.map { Double($0.ramUsage ?? 0) / 1_073_741_824 },
            cpuUsagePct: nil,
            ssdModel: nil
        )
    }
}
