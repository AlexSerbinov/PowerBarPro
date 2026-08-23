import Foundation
import Combine

/// Abstraction over persistent settings (UserDefaults, etc.).
/// Each setting has a typed getter/setter and a Combine publisher for reactivity.
protocol SettingsStorage: AnyObject {
    /// Power display mode for the menu bar.
    var displayMode: DisplayMode { get set }
    var displayModePublisher: AnyPublisher<DisplayMode, Never> { get }

    /// Battery calculation averaging mode.
    var batteryDisplayMode: DisplayMode { get set }
    var batteryDisplayModePublisher: AnyPublisher<DisplayMode, Never> { get }

    /// macmon polling interval in milliseconds.
    var updateIntervalMs: Int { get set }
    var updateIntervalMsPublisher: AnyPublisher<Int, Never> { get }

    /// Averaging period for process power display (seconds). 0 = instant.
    var processAveragingSeconds: Int { get set }
    var processAveragingSecondsPublisher: AnyPublisher<Int, Never> { get }

    /// App language setting.
    var language: AppLanguage { get set }
    var languagePublisher: AnyPublisher<AppLanguage, Never> { get }

    /// Power-hog notifications on/off.
    var alertsEnabled: Bool { get set }
    var alertsEnabledPublisher: AnyPublisher<Bool, Never> { get }

    /// Per-app wattage threshold (W) that triggers a power-hog alert.
    var alertThresholdW: Int { get set }
    var alertThresholdWPublisher: AnyPublisher<Int, Never> { get }
}
