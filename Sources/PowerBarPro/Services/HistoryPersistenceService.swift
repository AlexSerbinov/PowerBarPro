import Foundation

/// Persists the PowerAggregator history across app restarts.
/// Loads saved readings on start, then snapshots the buffer periodically
/// and on demand (app termination).
final class HistoryPersistenceService {

    private let aggregator: PowerAggregating
    private let storageURL: URL
    private let saveInterval: TimeInterval
    private let maxAge: TimeInterval

    private var timer: Timer?
    private let ioQueue = DispatchQueue(label: "powerbarpro.history-persistence", qos: .utility)

    init(
        aggregator: PowerAggregating,
        storageURL: URL? = nil,
        saveInterval: TimeInterval = 60,
        maxAge: TimeInterval = Constants.Defaults.maxHistoryDuration
    ) {
        self.aggregator = aggregator
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.saveInterval = saveInterval
        self.maxAge = maxAge
    }

    // MARK: - Public

    /// Load persisted history into the aggregator and begin periodic saves.
    func start() {
        restore()
        let timer = Timer(timeInterval: saveInterval, repeats: true) { [weak self] _ in
            self?.saveAsync()
        }
        timer.tolerance = saveInterval / 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Synchronous save — call from applicationWillTerminate.
    func saveNow() {
        let readings = aggregator.readings(for: 0)
        write(readings)
    }

    // MARK: - Private

    func restore() {
        guard let data = try? Data(contentsOf: storageURL),
              let readings = try? JSONDecoder().decode([PowerReading].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let fresh = readings.filter { $0.timestamp >= cutoff }
        guard !fresh.isEmpty else { return }
        aggregator.restore(fresh)
    }

    private func saveAsync() {
        let readings = aggregator.readings(for: 0)
        ioQueue.async { [weak self] in
            self?.write(readings)
        }
    }

    private func write(_ readings: [PowerReading]) {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("PowerBarPro")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
}
