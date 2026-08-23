import Foundation
import Combine
@testable import PowerBarPro

/// Mock settings for testing. Stores values in memory, no persistence.
final class MockSettingsStore: SettingsStorage {

    @Published var displayMode: DisplayMode
    @Published var batteryDisplayMode: DisplayMode
    @Published var updateIntervalMs: Int
    @Published var processAveragingSeconds: Int
    @Published var language: AppLanguage
    @Published var alertsEnabled: Bool = true
    @Published var alertThresholdW: Int = Constants.Defaults.alertThresholdW

    var alertsEnabledPublisher: AnyPublisher<Bool, Never> {
        $alertsEnabled.eraseToAnyPublisher()
    }
    var alertThresholdWPublisher: AnyPublisher<Int, Never> {
        $alertThresholdW.eraseToAnyPublisher()
    }

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

    init(
        displayMode: DisplayMode = Constants.Defaults.displayMode,
        batteryDisplayMode: DisplayMode = Constants.Defaults.batteryDisplayMode,
        updateIntervalMs: Int = Constants.Defaults.updateIntervalMs,
        processAveragingSeconds: Int = Constants.Defaults.processAveragingSeconds,
        language: AppLanguage = .english
    ) {
        self.displayMode = displayMode
        self.batteryDisplayMode = batteryDisplayMode
        self.updateIntervalMs = updateIntervalMs
        self.processAveragingSeconds = processAveragingSeconds
        self.language = language
    }
}
