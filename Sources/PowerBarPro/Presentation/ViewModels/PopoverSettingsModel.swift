import Foundation
import Combine

/// Reactive bridge between `SettingsStorage` (protocol, not observable) and
/// SwiftUI popover views. Without it, setting rows render stale values:
/// the popover body isn't re-evaluated when a plain protocol property changes.
final class PopoverSettingsModel: ObservableObject {

    /// 0 = instant; otherwise averaging window in seconds.
    @Published var displayModeSeconds: Int
    /// Averaging window (seconds) used for the battery time-remaining estimate.
    @Published var batteryModeSeconds: Int
    @Published var processAveragingSeconds: Int
    @Published var updateIntervalMs: Int

    private let settings: SettingsStorage
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStorage) {
        self.settings = settings
        self.displayModeSeconds = Self.seconds(of: settings.displayMode)
        self.batteryModeSeconds = Self.seconds(of: settings.batteryDisplayMode)
        self.processAveragingSeconds = settings.processAveragingSeconds
        self.updateIntervalMs = settings.updateIntervalMs

        bindStorageToModel()
        bindModelToStorage()
    }

    // MARK: - Private

    private func bindStorageToModel() {
        settings.displayModePublisher
            .dropFirst()  // initial value read synchronously in init; async replay may be stale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                let s = Self.seconds(of: mode)
                if self?.displayModeSeconds != s { self?.displayModeSeconds = s }
            }
            .store(in: &cancellables)

        settings.batteryDisplayModePublisher
            .dropFirst()  // initial value read synchronously in init; async replay may be stale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                let s = Self.seconds(of: mode)
                if self?.batteryModeSeconds != s { self?.batteryModeSeconds = s }
            }
            .store(in: &cancellables)

        settings.processAveragingSecondsPublisher
            .dropFirst()  // initial value read synchronously in init; async replay may be stale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                if self?.processAveragingSeconds != s { self?.processAveragingSeconds = s }
            }
            .store(in: &cancellables)

        settings.updateIntervalMsPublisher
            .dropFirst()  // initial value read synchronously in init; async replay may be stale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ms in
                if self?.updateIntervalMs != ms { self?.updateIntervalMs = ms }
            }
            .store(in: &cancellables)
    }

    private func bindModelToStorage() {
        $displayModeSeconds
            .dropFirst()
            .sink { [weak self] s in
                let mode = Self.mode(from: s)
                if self?.settings.displayMode != mode { self?.settings.displayMode = mode }
            }
            .store(in: &cancellables)

        $batteryModeSeconds
            .dropFirst()
            .sink { [weak self] s in
                let mode = Self.mode(from: s)
                if self?.settings.batteryDisplayMode != mode { self?.settings.batteryDisplayMode = mode }
            }
            .store(in: &cancellables)

        $processAveragingSeconds
            .dropFirst()
            .sink { [weak self] s in
                if self?.settings.processAveragingSeconds != s { self?.settings.processAveragingSeconds = s }
            }
            .store(in: &cancellables)

        $updateIntervalMs
            .dropFirst()
            .sink { [weak self] ms in
                if self?.settings.updateIntervalMs != ms { self?.settings.updateIntervalMs = ms }
            }
            .store(in: &cancellables)
    }

    private static func seconds(of mode: DisplayMode) -> Int {
        switch mode {
        case .instant: return 0
        case .average(let s): return s
        }
    }

    private static func mode(from seconds: Int) -> DisplayMode {
        seconds == 0 ? .instant : .average(seconds: seconds)
    }
}
