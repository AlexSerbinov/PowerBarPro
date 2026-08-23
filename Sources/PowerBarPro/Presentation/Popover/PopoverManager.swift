import Cocoa
import SwiftUI

/// Manages an NSPopover that shows the SwiftUI PowerBarPopoverView.
final class PopoverManager {

    private var popover: NSPopover?
    private var eventMonitor: Any?

    private let powerVM: PowerDisplayViewModel
    private let batteryVM: BatteryViewModel
    private let processVM: ProcessListViewModel
    var settings: SettingsStorage?
    var onQuit: (() -> Void)?

    init(
        powerVM: PowerDisplayViewModel,
        batteryVM: BatteryViewModel,
        processVM: ProcessListViewModel
    ) {
        self.powerVM = powerVM
        self.batteryVM = batteryVM
        self.processVM = processVM
    }

    /// Create and configure the popover (call once during setup).
    func createPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let contentView = PowerBarPopoverView(
            powerVM: powerVM,
            batteryVM: batteryVM,
            processVM: processVM,
            settings: settings,
            onQuit: onQuit
        )

        let hostingController = NSHostingController(rootView: contentView)

        // Calculate max height: screen visible area minus margins
        let maxHeight: CGFloat
        if let screen = NSScreen.main {
            // visibleFrame already excludes menu bar and dock
            let available = screen.visibleFrame.height
            maxHeight = min(available - 100, 630) // 100px margin from edges, cap at 580
        } else {
            maxHeight = 500
        }

        popover.contentSize = NSSize(width: 340, height: maxHeight)
        popover.contentViewController = hostingController
        self.popover = popover
        return popover
    }

    /// Toggle popover visibility relative to the given status bar button.
    func toggle(relativeTo button: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    func close() {
        popover?.performClose(nil)
        stopEventMonitor()
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
