import Cocoa
import Combine

/// Manages the NSStatusItem and coordinates between ViewModels and MenuBuilder.
/// This is the "glue" layer — thin, delegates everything to VMs and builder.
final class MenuBarManager: NSObject {

    private var statusItem: NSStatusItem?
    private let menuBuilder = MenuBuilder()
    private var popoverManager: PopoverManager?

    private let powerDisplayVM: PowerDisplayViewModel
    private let batteryVM: BatteryViewModel
    private let processListVM: ProcessListViewModel
    private let settings: SettingsStorage
    private var cancellables = Set<AnyCancellable>()

    private let processDescriptionService: ProcessDescriptionService?

    init(
        powerDisplayVM: PowerDisplayViewModel,
        batteryVM: BatteryViewModel,
        processListVM: ProcessListViewModel,
        settings: SettingsStorage,
        processDescriptionService: ProcessDescriptionService? = nil
    ) {
        self.powerDisplayVM = powerDisplayVM
        self.batteryVM = batteryVM
        self.processListVM = processListVM
        self.settings = settings
        self.processDescriptionService = processDescriptionService
    }

    // MARK: - Lifecycle

    func setup() {
        // Wire LLM service + language into menu builder
        menuBuilder.processDescriptionService = processDescriptionService
        menuBuilder.currentLanguage = settings.language.rawValue

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

        // Left click → popover, right click → menu
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Build NSMenu for right-click
        let menu = menuBuilder.buildMenu(
            currentDisplayMode: settings.displayMode,
            currentBatteryMode: settings.batteryDisplayMode,
            currentIntervalMs: settings.updateIntervalMs,
            currentProcessAvgSecs: settings.processAveragingSeconds
        )
        // Don't assign menu directly — we handle clicks manually
        statusItem?.menu = nil

        // Create popover with settings + quit action
        let pm = PopoverManager(
            powerVM: powerDisplayVM,
            batteryVM: batteryVM,
            processVM: processListVM
        )
        pm.settings = settings
        pm.onQuit = { NSApplication.shared.terminate(nil) }
        popoverManager = pm
        _ = pm.createPopover()

        // Store menu for right-click usage
        self.rightClickMenu = menu
    }

    private var rightClickMenu: NSMenu?

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right click → show menu
            if let menu = rightClickMenu {
                statusItem?.menu = menu
                button.performClick(nil)
                // Reset so next left click goes to popover
                DispatchQueue.main.async { self.statusItem?.menu = nil }
            }
        } else {
            // Left click → show popover
            popoverManager?.toggle(relativeTo: button)
        }
    }

    private func wireMenuActions() {
        menuBuilder.onDisplayModeSelected = { [weak self] mode in
            self?.settings.displayMode = mode
        }

        menuBuilder.onBatteryModeSelected = { [weak self] mode in
            self?.settings.batteryDisplayMode = mode
            self?.batteryVM.refresh(currentMetrics: self?.powerDisplayVM.currentMetrics)
        }

        menuBuilder.onIntervalSelected = { [weak self] interval in
            self?.settings.updateIntervalMs = interval
        }

        menuBuilder.onProcessTerminate = { [weak self] info in
            _ = self?.processListVM.terminateProcess(info)
        }

        menuBuilder.onProcessAveragingSelected = { [weak self] secs in
            self?.settings.processAveragingSeconds = secs
        }

        menuBuilder.onLanguageSelected = { [weak self] lang in
            self?.settings.language = lang
            self?.menuBuilder.currentLanguage = lang.rawValue
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

        // Process averaging setting → ProcessListViewModel
        settings.processAveragingSecondsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] secs in
                self?.processListVM.averagingSeconds = secs
            }
            .store(in: &cancellables)

        // Refresh battery + process list on every metrics update
        powerDisplayVM.$currentMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.batteryVM.refresh(currentMetrics: metrics)
                self?.processListVM.refresh(metrics: metrics)
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

        // Display power
        processListVM.$displayPowerText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.menuBuilder.displayPowerItem?.title = text
            }
            .store(in: &cancellables)

        // Process list (uses attributed processes for accurate power values)
        processListVM.$attributedProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] attributed in
                guard let self = self, let menu = self.rightClickMenu else { return }
                let sysW = self.powerDisplayVM.currentMetrics?.sysPowerW ?? 0
                // Convert attributed to ProcessPowerInfo for menu builder
                let infos = attributed.map { ap in
                    ProcessPowerInfo(
                        id: ap.id, name: ap.name,
                        powerWatts: ap.totalWatts,
                        percentOfSystem: ap.percentOfSystem,
                        memoryBytes: ap.memoryBytes,
                        pidCount: ap.pidCount, pids: ap.pids
                    )
                }
                self.menuBuilder.updateProcessList(menu: menu, processes: infos, systemPowerW: sysW)
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
