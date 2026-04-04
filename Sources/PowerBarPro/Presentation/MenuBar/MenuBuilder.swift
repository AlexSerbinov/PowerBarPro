import Cocoa

/// Builds and updates the NSMenu for the status bar item.
/// Pure construction logic — no state management, easy to test.
final class MenuBuilder {

    // MARK: - Actions (set by MenuBarManager)

    var onDisplayModeSelected: ((DisplayMode) -> Void)?
    var onBatteryModeSelected: ((DisplayMode) -> Void)?
    var onIntervalSelected: ((Int) -> Void)?
    var onQuit: (() -> Void)?

    // MARK: - Menu Item References

    private(set) var detailsItem: NSMenuItem?
    private(set) var batteryItem: NSMenuItem?

    // MARK: - Build

    func buildMenu(
        currentDisplayMode: DisplayMode,
        currentBatteryMode: DisplayMode,
        currentIntervalMs: Int
    ) -> NSMenu {
        let menu = NSMenu()

        // Power details (disabled info item)
        let details = NSMenuItem(title: "Power Details", action: nil, keyEquivalent: "")
        details.isEnabled = false
        detailsItem = details
        menu.addItem(details)

        menu.addItem(.separator())

        // Averaging period submenu
        let avgItem = NSMenuItem(
            title: "Averaging Period: \(currentDisplayMode.displayName)",
            action: nil, keyEquivalent: ""
        )
        avgItem.submenu = buildDisplayModeSubmenu(current: currentDisplayMode, isBattery: false)
        menu.addItem(avgItem)

        menu.addItem(.separator())

        // Refresh rate submenu
        let intervalItem = NSMenuItem(
            title: "Refresh Rate: \(currentIntervalMs)ms",
            action: nil, keyEquivalent: ""
        )
        intervalItem.submenu = buildIntervalSubmenu(current: currentIntervalMs)
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        // Battery time
        let battery = NSMenuItem(title: "Battery: Calculating...", action: nil, keyEquivalent: "")
        battery.submenu = buildDisplayModeSubmenu(current: currentBatteryMode, isBattery: true)
        batteryItem = battery
        menu.addItem(battery)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit PowerBar", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
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

        // Instant option
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

        // Average options
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

    @objc private func quitClicked() {
        onQuit?()
    }
}
