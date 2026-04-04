import Foundation
import Combine
@testable import PowerBarPro

/// Mock settings for testing. Stores values in memory, no persistence.
final class MockSettingsStore: SettingsStorage {

    @Published var displayMode: DisplayMode
    @Published var batteryDisplayMode: DisplayMode
    @Published var updateIntervalMs: Int

    var displayModePublisher: AnyPublisher<DisplayMode, Never> {
        $displayMode.eraseToAnyPublisher()
    }
    var batteryDisplayModePublisher: AnyPublisher<DisplayMode, Never> {
        $batteryDisplayMode.eraseToAnyPublisher()
    }
    var updateIntervalMsPublisher: AnyPublisher<Int, Never> {
        $updateIntervalMs.eraseToAnyPublisher()
    }

    init(
        displayMode: DisplayMode = Constants.Defaults.displayMode,
        batteryDisplayMode: DisplayMode = Constants.Defaults.batteryDisplayMode,
        updateIntervalMs: Int = Constants.Defaults.updateIntervalMs
    ) {
        self.displayMode = displayMode
        self.batteryDisplayMode = batteryDisplayMode
        self.updateIntervalMs = updateIntervalMs
    }
}
