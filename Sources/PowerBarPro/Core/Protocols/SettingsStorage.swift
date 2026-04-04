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
}
