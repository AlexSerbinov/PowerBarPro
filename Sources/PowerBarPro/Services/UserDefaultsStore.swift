import Foundation
import Combine

/// Persistent settings backed by UserDefaults.
/// Each property is cached in a @Published var for reactive UI updates.
final class UserDefaultsStore: SettingsStorage {

    private enum Keys {
        static let displayMode = "powerbar.displayMode"
        static let batteryDisplayMode = "powerbar.batteryDisplayMode"
        static let updateIntervalMs = "powerbar.updateIntervalMs"
        static let processAveragingSeconds = "powerbar.processAveragingSeconds"
        static let language = "powerbar.language"
    }

    // MARK: - Backing storage

    @Published var displayMode: DisplayMode
    @Published var batteryDisplayMode: DisplayMode
    @Published var updateIntervalMs: Int
    @Published var processAveragingSeconds: Int
    @Published var language: AppLanguage

    // MARK: - Publishers

    var displayModePublisher: AnyPublisher<DisplayMode, Never> {
        $displayMode.eraseToAnyPublisher()
    }
    var batteryDisplayModePublisher: AnyPublisher<DisplayMode, Never> {
        $batteryDisplayMode.eraseToAnyPublisher()
    }
    var updateIntervalMsPublisher: AnyPublisher<Int, Never> {
        $updateIntervalMs.eraseToAnyPublisher()
    }
    var processAveragingSecondsPublisher: AnyPublisher<Int, Never> {
        $processAveragingSeconds.eraseToAnyPublisher()
    }
    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        $language.eraseToAnyPublisher()
    }

    // MARK: - Init

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load from UserDefaults with fallbacks
        self.displayMode = Self.loadDisplayMode(
            from: defaults, key: Keys.displayMode
        ) ?? Constants.Defaults.displayMode

        self.batteryDisplayMode = Self.loadDisplayMode(
            from: defaults, key: Keys.batteryDisplayMode
        ) ?? Constants.Defaults.batteryDisplayMode

        let savedInterval = defaults.integer(forKey: Keys.updateIntervalMs)
        self.updateIntervalMs = savedInterval > 0
            ? savedInterval
            : Constants.Defaults.updateIntervalMs

        let savedProcessAvg = defaults.integer(forKey: Keys.processAveragingSeconds)
        self.processAveragingSeconds = savedProcessAvg > 0
            ? savedProcessAvg
            : Constants.Defaults.processAveragingSeconds

        if let langStr = defaults.string(forKey: Keys.language),
           let savedLang = AppLanguage(rawValue: langStr) {
            self.language = savedLang
        } else {
            self.language = AppLanguage.system
        }

        // Sync L.lang with initial value
        L.lang = self.language

        // Auto-persist changes
        $displayMode
            .dropFirst()
            .sink { [weak self] mode in
                self?.saveDisplayMode(mode, key: Keys.displayMode)
            }
            .store(in: &cancellables)

        $batteryDisplayMode
            .dropFirst()
            .sink { [weak self] mode in
                self?.saveDisplayMode(mode, key: Keys.batteryDisplayMode)
            }
            .store(in: &cancellables)

        $updateIntervalMs
            .dropFirst()
            .sink { [weak self] interval in
                self?.defaults.set(interval, forKey: Keys.updateIntervalMs)
            }
            .store(in: &cancellables)

        $processAveragingSeconds
            .dropFirst()
            .sink { [weak self] secs in
                self?.defaults.set(secs, forKey: Keys.processAveragingSeconds)
            }
            .store(in: &cancellables)

        $language
            .dropFirst()
            .sink { [weak self] lang in
                self?.defaults.set(lang.rawValue, forKey: Keys.language)
                L.lang = lang
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private static func loadDisplayMode(from defaults: UserDefaults, key: String) -> DisplayMode? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DisplayMode.self, from: data)
    }

    private func saveDisplayMode(_ mode: DisplayMode, key: String) {
        if let data = try? JSONEncoder().encode(mode) {
            defaults.set(data, forKey: key)
        }
    }
}
