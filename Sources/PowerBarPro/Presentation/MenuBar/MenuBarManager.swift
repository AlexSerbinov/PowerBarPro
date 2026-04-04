import Cocoa
import Combine

/// Manages the NSStatusItem and coordinates between ViewModels and MenuBuilder.
/// This is the "glue" layer — thin, delegates everything to VMs and builder.
final class MenuBarManager {

    private var statusItem: NSStatusItem?
    private let menuBuilder = MenuBuilder()

    private let powerDisplayVM: PowerDisplayViewModel
    private let batteryVM: BatteryViewModel
    private let settings: SettingsStorage
    private var cancellables = Set<AnyCancellable>()

    init(
        powerDisplayVM: PowerDisplayViewModel,
        batteryVM: BatteryViewModel,
        settings: SettingsStorage
    ) {
        self.powerDisplayVM = powerDisplayVM
        self.batteryVM = batteryVM
        self.settings = settings
    }

    // MARK: - Lifecycle

    func setup() {
        createStatusItem()
        wireMenuActions()
        bindViewModels()
    }

    func tearDown() {
        if let item = statusItem {
            item.statusBar?.removeStatusItem(item)
        }
        statusItem = nil
        cancellables.removeAll()
    }

    // MARK: - Private: Setup

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        button.title = "Loading..."
        button.font = NSFont.monospacedDigitSystemFont(
            ofSize: Constants.UI.menuBarFontSize,
            weight: .regular
        )

        let menu = menuBuilder.buildMenu(
            currentDisplayMode: settings.displayMode,
            currentBatteryMode: settings.batteryDisplayMode,
            currentIntervalMs: settings.updateIntervalMs
        )
        statusItem?.menu = menu
    }

    private func wireMenuActions() {
        menuBuilder.onDisplayModeSelected = { [weak self] mode in
            self?.settings.displayMode = mode
        }

        menuBuilder.onBatteryModeSelected = { [weak self] mode in
            self?.settings.batteryDisplayMode = mode
            self?.batteryVM.refresh(currentMetrics: nil)
        }

        menuBuilder.onIntervalSelected = { [weak self] interval in
            self?.settings.updateIntervalMs = interval
        }

        menuBuilder.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    private func bindViewModels() {
        // Power display → menu bar title
        powerDisplayVM.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.statusItem?.button?.title = text
            }
            .store(in: &cancellables)

        // Tooltip
        powerDisplayVM.$tooltipText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.statusItem?.button?.toolTip = text
            }
            .store(in: &cancellables)

        // Error state appearance
        powerDisplayVM.$isError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isError in
                self?.statusItem?.button?.appearsDisabled = isError
            }
            .store(in: &cancellables)

        // Details menu item
        powerDisplayVM.$detailsText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.menuBuilder.detailsItem?.title = text
            }
            .store(in: &cancellables)

        // Battery display
        batteryVM.$batteryText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.menuBuilder.batteryItem?.title = text
            }
            .store(in: &cancellables)

        batteryVM.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.menuBuilder.batteryItem?.isHidden = !visible
            }
            .store(in: &cancellables)

        // Settings changes → update checkmarks
        settings.displayModePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let menu = self?.statusItem?.menu else { return }
                self?.menuBuilder.updateDisplayModeCheckmarks(menu: menu, mode: mode)
            }
            .store(in: &cancellables)

        settings.batteryDisplayModePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.menuBuilder.updateBatteryModeCheckmarks(mode: mode)
            }
            .store(in: &cancellables)

        settings.updateIntervalMsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                guard let menu = self?.statusItem?.menu else { return }
                self?.menuBuilder.updateIntervalCheckmarks(menu: menu, intervalMs: interval)
            }
            .store(in: &cancellables)
    }
}
