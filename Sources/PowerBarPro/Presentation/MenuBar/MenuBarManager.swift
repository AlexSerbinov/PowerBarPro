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

    // MARK: - Background-cost controls

    /// Battery state comes from an `ioreg` subprocess — spawning one every
    /// metrics tick (1s) is the single biggest self-cost. Estimates change
    /// slowly; refresh every 30s and on battery-mode changes.
    private var lastBatteryRefresh: Date = .distantPast
    private let batteryRefreshInterval: TimeInterval = 30

    /// Power source from the previous metrics tick — unplugging/plugging
    /// the charger must recalculate the battery estimate immediately, not
    /// after the 30s throttle.
    private var lastExternalConnected: Bool?

    /// True while the right-click menu is open (NSMenuDelegate).
    private var isMenuOpen = false

    init(
        powerDisplayVM: PowerDisplayViewModel,
        batteryVM: BatteryViewModel,
        processListVM: ProcessListViewModel,
        settings: SettingsStorage
    ) {
        self.powerDisplayVM = powerDisplayVM
        self.batteryVM = batteryVM
        self.processListVM = processListVM
        self.settings = settings
    }

    // MARK: - Lifecycle

    func setup() {
        menuBuilder.currentLanguage = settings.language.rawValue

        createStatusItem()
        wireMenuActions()
        bindViewModels()
        listenForRemoteOpen()
    }

    /// Dev/automation hook: `notifyutil`-style distributed notification opens
    /// the popover and writes its window frame (top-left origin, points) to
    /// /tmp/powerbarpro_popover_frame.txt — used for docs screenshots.
    private func listenForRemoteOpen() {
        // Scripting hook: toggle keep-awake (indefinite) from the outside —
        // `notifyutil`-style senders, Karabiner, shell scripts.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.powerbarpro.keepAwake.toggle"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let keepAwake = self?.popoverManager?.keepAwake else { return }
            if keepAwake.isActive {
                keepAwake.stop()
            } else {
                keepAwake.start(duration: nil)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.powerbarpro.showPopover"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let button = self.statusItem?.button else {
                try? "no-button".write(toFile: "/tmp/powerbarpro_popover_frame.txt", atomically: true, encoding: .utf8)
                return
            }
            if !(self.popoverManager?.isShown ?? false) {
                self.popoverManager?.toggle(relativeTo: button)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let frame = self.popoverManager?.currentWindowFrame() else {
                    try? "no-window".write(toFile: "/tmp/powerbarpro_popover_frame.txt", atomically: true, encoding: .utf8)
                    return
                }
                let screenH = NSScreen.screens.first?.frame.height ?? 0
                let top = screenH - (frame.origin.y + frame.height)
                let line = "\(Int(frame.origin.x)) \(Int(top)) \(Int(frame.width)) \(Int(frame.height))"
                try? line.write(toFile: "/tmp/powerbarpro_popover_frame.txt", atomically: true, encoding: .utf8)
            }
        }
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
        pm.onVisibilityChange = { [weak self] shown in
            self?.updateProcessUIVisibility()
            if shown {
                // Battery line should be fresh when the user opens the popover
                self?.lastBatteryRefresh = Date()
                self?.batteryVM.refresh(currentMetrics: self?.powerDisplayVM.currentMetrics)
            }
        }
        popoverManager = pm
        _ = pm.createPopover()

        // Store menu for right-click usage
        menu.delegate = self
        self.rightClickMenu = menu
    }

    /// Process scanning runs at full cadence only while some UI shows it.
    private func updateProcessUIVisibility() {
        processListVM.isUIVisible = isMenuOpen || (popoverManager?.isShown ?? false)
    }

    // MARK: - Status button rendering (watts + fan-load bar)

    /// The thin fan-load bar overlaid at the bottom of the status button.
    private var fanBarView: FanBarView?

    /// Menu bar content: native wattage title + a thin fan-load bar pinned
    /// to the bottom of the status button (MacFans-style), color-coded by
    /// load. Falls back to plain text on fanless Macs; if the system ever
    /// refuses to composite the subview, the title alone still renders.
    private func updateStatusButton(text: String) {
        guard let button = statusItem?.button else { return }
        button.title = text

        guard let fraction = Self.fanLoadFraction(powerDisplayVM.currentMetrics) else {
            fanBarView?.isHidden = true
            return
        }

        let bar = ensureFanBarView(in: button)
        bar.isHidden = false
        bar.update(fraction: fraction, color: currentBarColor(loadFraction: fraction))
    }

    /// Fill = how hard the fans work; COLOR = which mode owns them (shared
    /// mode palette). Without the MacFans daemon the mode is unknown, so
    /// color degrades to a load scale (green/blue/orange — never red).
    private func currentBarColor(loadFraction: Double) -> NSColor {
        if let reply = popoverManager?.fanControlVM.reply {
            return MacFans.modeTint(mode: reply.mode, pct: reply.pct)
        }
        return Self.fanBarColor(loadFraction)
    }

    private func ensureFanBarView(in button: NSStatusBarButton) -> FanBarView {
        if let bar = fanBarView, bar.superview === button { return bar }

        let bar = FanBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 5),
            bar.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -5),
            bar.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1.5),
            bar.heightAnchor.constraint(equalToConstant: 3),
        ])
        fanBarView = bar
        return bar
    }

    /// Highest fan load across all fans, normalized to 0...1 by each fan's
    /// min/max RPM range. Nil when the machine has no fans.
    static func fanLoadFraction(_ metrics: SystemMetrics?) -> Double? {
        fanLoadFraction(fans: metrics?.fans ?? [])
    }

    static func fanLoadFraction(fans: [FanMetrics]) -> Double? {
        guard !fans.isEmpty else { return nil }
        let fractions = fans.compactMap { fan -> Double? in
            let minR = fan.minRpm ?? 0
            guard let maxR = fan.maxRpm, maxR > minR else { return nil }
            return max(0, min(1, (fan.actualRpm - minR) / (maxR - minR)))
        }
        return fractions.max()
    }

    static func fanBarColor(_ fraction: Double) -> NSColor {
        switch fraction {
        case ..<0.4: return .systemGreen
        case ..<0.75: return .systemBlue
        default: return .systemOrange
        }
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
        // Power display → menu bar title (with fan-load bar when fans exist)
        powerDisplayVM.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.updateStatusButton(text: text)
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

        // Refresh battery (throttled) + process list on metrics updates.
        // A power-source change (charger plugged/unplugged) bypasses the
        // throttle so the time-remaining estimate updates within a tick.
        powerDisplayVM.$currentMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self = self else { return }
                let now = Date()

                let externalNow = metrics?.battery?.externalConnected
                let powerSourceChanged = externalNow != nil
                    && self.lastExternalConnected != nil
                    && externalNow != self.lastExternalConnected
                if externalNow != nil { self.lastExternalConnected = externalNow }

                if powerSourceChanged
                    || now.timeIntervalSince(self.lastBatteryRefresh) >= self.batteryRefreshInterval {
                    self.lastBatteryRefresh = now
                    self.batteryVM.refresh(currentMetrics: metrics)
                }
                self.processListVM.refresh(metrics: metrics)
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

        // Process list (uses attributed processes for accurate power values).
        // Rebuilding NSMenuItems + icons + LLM prefetch is pointless while
        // the menu is hidden — rebuild only when it's actually open.
        processListVM.$attributedProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] attributed in
                guard let self = self, self.isMenuOpen, let menu = self.rightClickMenu else { return }
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

// MARK: - NSMenuDelegate (right-click menu visibility)

extension MenuBarManager: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === rightClickMenu else { return }
        isMenuOpen = true
        updateProcessUIVisibility()
        // Populate immediately with the freshest data we have
        let sysW = powerDisplayVM.currentMetrics?.sysPowerW ?? 0
        let infos = processListVM.attributedProcesses.map { ap in
            ProcessPowerInfo(
                id: ap.id, name: ap.name,
                powerWatts: ap.totalWatts,
                percentOfSystem: ap.percentOfSystem,
                memoryBytes: ap.memoryBytes,
                pidCount: ap.pidCount, pids: ap.pids
            )
        }
        menuBuilder.updateProcessList(menu: menu, processes: infos, systemPowerW: sysW)
        // Battery line should be fresh when the user actually looks at it
        lastBatteryRefresh = Date()
        batteryVM.refresh(currentMetrics: powerDisplayVM.currentMetrics)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === rightClickMenu else { return }
        isMenuOpen = false
        updateProcessUIVisibility()
    }
}

// MARK: - Fan bar view (bottom of the status button)

/// Thin rounded progress bar (track + colored fill) drawn with NSBezierPath.
final class FanBarView: NSView {

    private var fraction: Double = 0
    private var fillColor: NSColor = .systemGreen

    func update(fraction: Double, color: NSColor) {
        let clamped = max(0, min(1, fraction))
        if clamped != self.fraction || color != fillColor {
            self.fraction = clamped
            self.fillColor = color
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2

        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let fill = NSRect(
            x: 0, y: 0,
            width: max(bounds.height, bounds.width * CGFloat(fraction)),
            height: bounds.height
        )
        fillColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }

    /// The bar is decorative — clicks belong to the status button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
