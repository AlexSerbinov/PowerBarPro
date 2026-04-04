import Foundation
import Combine

/// Manages the `macmon pipe` subprocess for real-time power metrics.
/// Emits parsed `PowerMetrics` through Combine publishers.
final class MacMonService: PowerMonitoring {

    // MARK: - Published state

    private let metricsSubject = CurrentValueSubject<PowerMetrics?, Never>(nil)
    private let errorSubject = CurrentValueSubject<AppError?, Never>(nil)
    private let isRunningSubject = CurrentValueSubject<Bool, Never>(false)

    var metricsPublisher: AnyPublisher<PowerMetrics?, Never> {
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
    private var macmonProcess: Process?
    private var updateIntervalMs: Int = Constants.Defaults.updateIntervalMs
    private let decoder = JSONDecoder()

    // MARK: - Init

    init(processRunner: ProcessRunning) {
        self.processRunner = processRunner
    }

    // MARK: - PowerMonitoring

    func startMonitoring() {
        guard !isRunningSubject.value else { return }

        guard let macmonPath = processRunner.findExecutable(
            name: Constants.MacMon.binaryName,
            searchPaths: Constants.MacMon.searchPaths
        ) else {
            errorSubject.send(.macmonNotFound)
            return
        }

        let (process, pipe) = processRunner.createStreamingProcess(
            executablePath: macmonPath,
            arguments: ["pipe", "--interval", "\(updateIntervalMs)"]
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
            self?.processOutput(output)
        }

        do {
            try process.run()
            macmonProcess = process
            isRunningSubject.send(true)
            errorSubject.send(nil)
        } catch {
            errorSubject.send(.macmonStartFailed(error.localizedDescription))
        }
    }

    func stopMonitoring() {
        guard isRunningSubject.value else { return }
        macmonProcess?.terminate()
        macmonProcess = nil
        isRunningSubject.send(false)
        metricsSubject.send(nil)
        errorSubject.send(nil)
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

    private func processOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else { continue }

            do {
                let metrics = try decoder.decode(PowerMetrics.self, from: data)
                DispatchQueue.main.async {
                    self.metricsSubject.send(metrics)
                }
            } catch {
                // Individual line parse failures are expected (partial lines).
                // Don't propagate to error state.
            }
        }
    }
}
