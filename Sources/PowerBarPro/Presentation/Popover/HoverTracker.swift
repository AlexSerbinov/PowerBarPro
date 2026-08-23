import SwiftUI
import AppKit

/// Reliable hover detection backed by a real NSTrackingArea.
///
/// SwiftUI's `.onHover` loses mouseEntered/Exited events when the hierarchy
/// re-renders every second (live wattage updates rebuild the popover body,
/// and the re-created tracking areas miss events until the cursor leaves
/// and re-enters). An NSView with `.inVisibleRect` tracking follows its
/// bounds automatically and never needs re-registration.
struct HoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            onChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onChange?(false)
        }

        /// Tracking only — clicks pass through to SwiftUI content.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    /// Drop-in replacement for `.onHover` that survives constant re-renders.
    func reliableHover(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: onChange))
    }
}
