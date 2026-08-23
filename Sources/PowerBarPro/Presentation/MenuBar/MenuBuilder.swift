import Cocoa

/// Builds and updates the NSMenu for the status bar item.
/// Inherits NSObject for Objective-C runtime compatibility (@objc selectors).
final class MenuBuilder: NSObject {

    // MARK: - Actions (set by MenuBarManager)

    var onDisplayModeSelected: ((DisplayMode) -> Void)?
    var onBatteryModeSelected: ((DisplayMode) -> Void)?
    var onIntervalSelected: ((Int) -> Void)?
    var onProcessTerminate: ((ProcessPowerInfo) -> Void)?
    var onProcessAveragingSelected: ((Int) -> Void)?
    var onLanguageSelected: ((AppLanguage) -> Void)?
    var onQuit: (() -> Void)?

    // MARK: - Menu Item References

    private(set) var detailsItem: NSMenuItem?
    private(set) var batteryItem: NSMenuItem?
    private(set) var displayPowerItem: NSMenuItem?
    private(set) var processMenuItems: [NSMenuItem] = []
    private(set) var processSectionHeader: NSMenuItem?

    // Process data for terminate actions
    private var processMap: [Int: ProcessPowerInfo] = [:]  // tag → info

    /// Injected by MenuBarManager for LLM tooltips
    var processDescriptionService: ProcessDescriptionService?
    var currentLanguage: String = "en"

    // MARK: - Build

    func buildMenu(
        currentDisplayMode: DisplayMode,
        currentBatteryMode: DisplayMode,
        currentIntervalMs: Int,
        currentProcessAvgSecs: Int = Constants.Defaults.processAveragingSeconds
    ) -> NSMenu {
        let menu = NSMenu()

        // Power details (disabled info item)
        let details = NSMenuItem(title: L.powerDetails, action: nil, keyEquivalent: "")
        details.isEnabled = false
        detailsItem = details
        menu.addItem(details)

        menu.addItem(.separator())

        // Display power
        let displayItem = NSMenuItem(title: "Display: --", action: nil, keyEquivalent: "")
        displayItem.isEnabled = false
        displayPowerItem = displayItem
        menu.addItem(displayItem)

        menu.addItem(.separator())

        // Averaging period submenu
        let avgItem = NSMenuItem(
            title: "\(L.averagingPeriod): \(currentDisplayMode.displayName)",
            action: nil, keyEquivalent: ""
        )
        avgItem.submenu = buildDisplayModeSubmenu(current: currentDisplayMode, isBattery: false)
        menu.addItem(avgItem)

        menu.addItem(.separator())

        // Refresh rate submenu
        let intervalItem = NSMenuItem(
            title: "\(L.refreshRate): \(currentIntervalMs)ms",
            action: nil, keyEquivalent: ""
        )
        intervalItem.submenu = buildIntervalSubmenu(current: currentIntervalMs)
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        // Battery time
        let battery = NSMenuItem(title: "\(L.battery): \(L.calculating)", action: nil, keyEquivalent: "")
        battery.submenu = buildDisplayModeSubmenu(current: currentBatteryMode, isBattery: true)
        batteryItem = battery
        menu.addItem(battery)

        menu.addItem(.separator())

        // Process averaging submenu
        let processAvgItem = NSMenuItem(
            title: "\(L.processAveraging): \(processAveragingName(currentProcessAvgSecs))",
            action: nil, keyEquivalent: ""
        )
        processAvgItem.submenu = buildProcessAveragingSubmenu(current: currentProcessAvgSecs)
        menu.addItem(processAvgItem)

        menu.addItem(.separator())

        // Process list header
        let processHeader = NSMenuItem(title: L.activeProcesses, action: nil, keyEquivalent: "")
        processHeader.isEnabled = false
        processSectionHeader = processHeader
        menu.addItem(processHeader)

        // Process items placeholder (will be populated dynamically)
        // We reserve space with a "Loading..." item
        let loadingItem = NSMenuItem(title: "  \(L.loading)", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        processMenuItems = [loadingItem]
        menu.addItem(loadingItem)

        menu.addItem(.separator())

        // Quit
        // Language submenu
        let langItem = NSMenuItem(title: "\(L.language): \(L.lang.displayName)", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(languageClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = lang == .english ? 0 : 1
            item.state = lang == L.lang ? .on : .off
            langSubmenu.addItem(item)
        }
        langItem.submenu = langSubmenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L.quit, action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Dynamic Process List Update

    func updateProcessList(menu: NSMenu, processes: [ProcessPowerInfo], systemPowerW: Double) {
        // Remove old process items
        for item in processMenuItems {
            menu.removeItem(item)
        }
        processMenuItems.removeAll()
        processMap.removeAll()

        // Find insertion point (after process header)
        guard let header = processSectionHeader,
              let headerIndex = menu.items.firstIndex(of: header) else { return }

        var insertIndex = headerIndex + 1

        if processes.isEmpty {
            let empty = NSMenuItem(title: "  \(L.noActiveProcesses)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.insertItem(empty, at: insertIndex)
            processMenuItems.append(empty)
            return
        }

        // Show top 15 processes — clickable (terminate on click), with app icon + LLM tooltip
        let visible = Array(processes.prefix(15))

        // Pre-fetch LLM descriptions for all visible process names
        if let descService = processDescriptionService {
            descService.prefetch(
                processNames: visible.map(\.name),
                language: currentLanguage
            )
        }

        for (i, proc) in visible.enumerated() {
            let powerStr = Formatters.processWatts(proc.powerWatts)
            let pctStr = String(format: "%.1f%%", proc.percentOfSystem)
            let title = "\(proc.name)  \(powerStr) (\(pctStr))"

            // Check if we have LLM description cached
            let cachedDesc = processDescriptionService?.getCached(
                processName: proc.name,
                language: currentLanguage
            )

            let item = NSMenuItem(
                title: title,
                action: #selector(terminateProcessClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = i

            // Set tooltip: LLM description if cached, otherwise basic
            if let desc = cachedDesc {
                item.toolTip = desc.tooltip(processName: proc.name)
            } else {
                item.toolTip = "\(L.terminate) \(proc.name)"

                // Async fetch — update tooltip when ready
                let name = proc.name
                processDescriptionService?.getDescription(processName: name, language: currentLanguage) { [weak item] desc in
                    item?.toolTip = desc.tooltip(processName: name)
                }
            }

            // System processes: light red text
            if cachedDesc?.isSystem == true {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [
                        .foregroundColor: NSColor.systemRed.withAlphaComponent(0.7),
                        .font: NSFont.menuFont(ofSize: 0)
                    ]
                )
            }

            // App icon (appIcon returns it pre-sized 16x16)
            if let icon = Self.appIcon(for: proc.pids.first ?? 0) {
                item.image = icon
            }

            processMap[i] = proc
            menu.insertItem(item, at: insertIndex)
            processMenuItems.append(item)
            insertIndex += 1
        }
    }

    // MARK: - Update Helpers

    func updateDisplayModeCheckmarks(menu: NSMenu, mode: DisplayMode) {
        guard let avgItem = menu.items.first(where: { $0.title.hasPrefix("Averaging Period") }),
              let submenu = avgItem.submenu else { return }

        avgItem.title = "Averaging Period: \(mode.displayName)"
        applyCheckmarks(submenu: submenu, mode: mode)
    }

    func updateBatteryModeCheckmarks(mode: DisplayMode) {
        guard let submenu = batteryItem?.submenu else { return }
        applyCheckmarks(submenu: submenu, mode: mode)
    }

    func updateIntervalCheckmarks(menu: NSMenu, intervalMs: Int) {
        guard let intervalItem = menu.items.first(where: { $0.title.hasPrefix("Refresh Rate") }),
              let submenu = intervalItem.submenu else { return }

        intervalItem.title = "Refresh Rate: \(intervalMs)ms"
        for item in submenu.items {
            item.state = (item.tag == intervalMs) ? .on : .off
        }
    }

    // MARK: - Private: Submenus

    private func buildDisplayModeSubmenu(current: DisplayMode, isBattery: Bool) -> NSMenu {
        let submenu = NSMenu()

        let instant = NSMenuItem(
            title: "Instant",
            action: isBattery ? #selector(batteryModeClicked(_:)) : #selector(displayModeClicked(_:)),
            keyEquivalent: ""
        )
        instant.target = self
        instant.tag = -1
        instant.state = (current == .instant) ? .on : .off
        submenu.addItem(instant)

        submenu.addItem(.separator())

        for period in Constants.Defaults.availableAveragePeriods {
            let item = NSMenuItem(
                title: Formatters.periodName(period),
                action: isBattery ? #selector(batteryModeClicked(_:)) : #selector(displayModeClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = period
            if case .average(let s) = current, s == period {
                item.state = .on
            }
            submenu.addItem(item)
        }

        return submenu
    }

    private func buildIntervalSubmenu(current: Int) -> NSMenu {
        let submenu = NSMenu()

        for interval in Constants.Defaults.availableIntervals {
            let item = NSMenuItem(
                title: "\(interval)ms",
                action: #selector(intervalClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = interval
            item.state = (interval == current) ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    private func applyCheckmarks(submenu: NSMenu, mode: DisplayMode) {
        for item in submenu.items {
            if item.tag == -1 {
                item.state = (mode == .instant) ? .on : .off
            } else if item.tag >= 0 {
                if case .average(let s) = mode, s == item.tag {
                    item.state = .on
                } else {
                    item.state = .off
                }
            }
        }
    }

    // MARK: - Process Averaging Submenu

    private func buildProcessAveragingSubmenu(current: Int) -> NSMenu {
        let submenu = NSMenu()
        for period in Constants.Defaults.availableProcessAveragingPeriods {
            let name = processAveragingName(period)
            let item = NSMenuItem(
                title: name,
                action: #selector(processAveragingClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = period
            item.state = (period == current) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func processAveragingName(_ seconds: Int) -> String {
        if seconds == 0 { return "Instant (raw)" }
        return Formatters.periodName(seconds)
    }

    // MARK: - App Icon Resolution

    /// Cache: PID → icon (to avoid repeated lookups)
    private static var iconCache: [pid_t: NSImage] = [:]

    /// PIDs are recycled by the OS and dead entries accumulate — cap the cache.
    private static let iconCacheLimit = 512

    /// Get app icon for a PID by resolving the executable path to .app bundle.
    /// The returned image is already sized 16x16 — do not mutate it.
    static func appIcon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }

        // Get executable path via proc_pidpath
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let len = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        guard len > 0 else { return nil }

        let fullPath = String(cString: pathBuffer)

        let icon: NSImage
        if let range = fullPath.range(of: ".app/") ?? fullPath.range(of: ".app") {
            let appPath = String(fullPath[...range.lowerBound]) + "app"
            icon = NSWorkspace.shared.icon(forFile: appPath)
        } else {
            // No .app bundle — use generic executable icon
            icon = NSWorkspace.shared.icon(forFileType: "com.apple.application")
        }
        icon.size = NSSize(width: 16, height: 16)

        if iconCache.count >= iconCacheLimit {
            iconCache.removeAll()
        }
        iconCache[pid] = icon
        return icon
    }

    // MARK: - Actions

    @objc private func displayModeClicked(_ sender: NSMenuItem) {
        let mode: DisplayMode = sender.tag == -1
            ? .instant
            : .average(seconds: sender.tag)
        onDisplayModeSelected?(mode)
    }

    @objc private func batteryModeClicked(_ sender: NSMenuItem) {
        let mode: DisplayMode = sender.tag == -1
            ? .instant
            : .average(seconds: sender.tag)
        onBatteryModeSelected?(mode)
    }

    @objc private func intervalClicked(_ sender: NSMenuItem) {
        onIntervalSelected?(sender.tag)
    }

    @objc private func processAveragingClicked(_ sender: NSMenuItem) {
        onProcessAveragingSelected?(sender.tag)
    }

    @objc private func terminateProcessClicked(_ sender: NSMenuItem) {
        if let info = processMap[sender.tag] {
            onProcessTerminate?(info)
        }
    }

    @objc private func languageClicked(_ sender: NSMenuItem) {
        let lang: AppLanguage = sender.tag == 0 ? .english : .ukrainian
        onLanguageSelected?(lang)
    }

    @objc private func quitClicked() {
        onQuit?()
    }
}
