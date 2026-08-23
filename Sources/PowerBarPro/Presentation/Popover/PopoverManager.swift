import Cocoa
import SwiftUI

/// Manages an NSPopover that shows the SwiftUI PowerBarPopoverView.
///
/// The SwiftUI hosting controller is created on show and released on close:
/// a resident hosting view re-renders on every Combine tick (hero, cards,
/// chart downsampling) even while the popover is invisible, which wastes
/// CPU around the clock for a menu bar utility.
final class PopoverManager: NSObject, NSPopoverDelegate {

    private var popover: NSPopover?
    private var eventMonitor: Any?

    private let powerVM: PowerDisplayViewModel
    private let batteryVM: BatteryViewModel
    private let processVM: ProcessListViewModel
    private let agentSessionsVM = AgentSessionsViewModel()
    var settings: SettingsStorage?
    var onQuit: (() -> Void)?

    /// Reports show/close so consumers can pause background work.
    var onVisibilityChange: ((Bool) -> Void)?

    private(set) var isShown = false

    init(
        powerVM: PowerDisplayViewModel,
        batteryVM: BatteryViewModel,
        processVM: ProcessListViewModel
    ) {
        self.powerVM = powerVM
        self.batteryVM = batteryVM
        self.processVM = processVM
    }

    /// Create and configure the popover shell (call once during setup).
    /// Content is attached lazily on `toggle`.
    func createPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 420)
        self.popover = popover
        return popover
    }

    /// Toggle popover visibility relative to the given status bar button.
    func toggle(relativeTo button: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            close()
        } else {
            attachContent(to: popover)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            isShown = true
            onVisibilityChange?(true)
            startEventMonitor()
        }
    }

    func close() {
        popover?.performClose(nil)
        // popoverDidClose handles the teardown (also fires on outside-click)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        isShown = false
        stopEventMonitor()
        // Drop the SwiftUI tree so closed-popover ticks cost nothing
        popover?.contentViewController = nil
        onVisibilityChange?(false)
    }

    // MARK: - Private

    private func attachContent(to popover: NSPopover) {
        let contentView = PowerBarPopoverView(
            powerVM: powerVM,
            batteryVM: batteryVM,
            processVM: processVM,
            agentSessionsVM: agentSessionsVM,
            settingsModel: settings.map(PopoverSettingsModel.init),
            onQuit: onQuit,
            onHeightChange: { [weak popover, weak self] height in
                guard let popover, let self else { return }
                // Fit the popover to content; cap to the visible screen area
                let capped = min(height, self.maxContentHeight())
                if abs(popover.contentSize.height - capped) > 1 {
                    popover.contentSize = NSSize(width: 320, height: capped)
                }
            }
        )
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 320, height: 420)
    }

    private func maxContentHeight() -> CGFloat {
        if let screen = NSScreen.main {
            // visibleFrame already excludes menu bar and dock
            return min(screen.visibleFrame.height - 100, 630)
        }
        return 500
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
