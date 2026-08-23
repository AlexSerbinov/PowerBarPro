import AppKit
import SwiftUI

// Ephemeral fan-mode HUD — the little panel that flashes under the menu bar
// when the mode changes (fn+6/7/8/9 via Karabiner or a click in the popover).
// Ported from MacFans' ModeHUD: styled after the system volume HUD — no
// chrome, no interaction, gone in a moment.

extension MacFans.Reply {

    /// Human name for the HUD. Manual percentages get a name instead of a
    /// number, since the number is already on the line below.
    var hudTitle: String {
        switch mode {
        case .auto: return "Automatic"
        case .curve: return "Battery Curve"
        case .manual:
            switch pct {
            case 100: return "Full Blast"
            case 85...99: return "Aggressive"
            case 60..<85: return "Boost"
            case 40..<60: return "Balanced"
            default: return "Whisper"
            }
        }
    }

    /// Second HUD line: percentage, fastest fan, and the temperature that
    /// matters for the mode.
    var hudDetail: String {
        var parts: [String] = []
        if mode != .auto { parts.append("\(pct)%") }
        if !fans.isEmpty { parts.append("\(rpmText) rpm") }
        if mode == .curve, let b = batteryC {
            parts.append(String(format: "%.1f°C batt", b))
        } else if let t = tempC {
            parts.append(String(format: "%.0f°C", t))
        }
        return parts.joined(separator: "  ·  ")
    }

    /// 0…1 fill for the HUD bar. In auto the daemon owns no percentage, so
    /// the bar shows where the fastest fan actually sits in its min…max.
    var hudBarFraction: Double {
        if mode != .auto { return Swift.max(0, Swift.min(1, Double(pct) / 100)) }
        guard let fan = fans.max(by: { $0.rpm < $1.rpm }), fan.max > fan.min else { return 0 }
        let span = Double(fan.max - fan.min)
        return Swift.max(0, Swift.min(1, Double(fan.rpm - fan.min) / span))
    }

    /// One colour per mode — the shared mode palette (see MacFans.modeTint).
    var hudTint: Color {
        Color(nsColor: MacFans.modeTint(mode: mode, pct: pct))
    }

    var hudSymbol: String {
        switch mode {
        case .auto: return "wind"
        case .curve: return "thermometer"
        case .manual: return pct >= 100 ? "bolt.fill" : "gauge"
        }
    }
}

struct FanModeBadge: Equatable {
    var title: String
    var detail: String
    var symbol: String
    var fill: Double
    var accent: Color

    init(reply: MacFans.Reply) {
        title = reply.hudTitle
        detail = reply.hudDetail
        symbol = reply.hudSymbol
        fill = reply.hudBarFraction
        accent = reply.hudTint
    }

    init() {
        title = ""
        detail = ""
        symbol = "wind"
        fill = 0
        accent = .secondary
    }
}

final class FanHUDModel: ObservableObject {
    @Published var badge = FanModeBadge()
    @Published var visible = false
}

private struct FanHUDView: View {
    @ObservedObject var model: FanHUDModel

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(model.badge.accent.opacity(0.16))
                Image(systemName: model.badge.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.badge.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.badge.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(model.badge.detail)
                    .font(.system(size: 10.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                bar
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(width: FanHUDController.panelSize.width, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.26), radius: 13, y: 5)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible ? 1 : 0.95, anchor: .top)
        .offset(y: model.visible ? 0 : -10)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: model.visible)
        .padding(FanHUDController.shadowInset)   // room for the shadow to fall in
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(model.badge.accent)
                    .frame(width: max(2, geo.size.width * model.badge.fill))
                    .animation(.easeOut(duration: 0.25), value: model.badge.fill)
            }
        }
        .frame(height: 3)
    }
}

/// Borderless, click-through window pinned under the menu bar.
final class FanHUDController {
    static let panelSize = CGSize(width: 218, height: 66)
    static let shadowInset: CGFloat = 18
    private static let visibleFor: TimeInterval = 1.5

    private let model = FanHUDModel()
    private var window: NSWindow?
    private var hide: DispatchWorkItem?

    /// The window is created on first show — most sessions never open it.
    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let full = CGSize(width: Self.panelSize.width + Self.shadowInset * 2,
                          height: Self.panelSize.height + Self.shadowInset * 2)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: full),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false            // SwiftUI draws it, so it can animate with the panel
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: FanHUDView(model: model))
        self.window = window
        return window
    }

    func show(_ reply: MacFans.Reply) {
        let window = ensureWindow()
        model.badge = FanModeBadge(reply: reply)
        position(window)
        window.orderFrontRegardless()
        model.visible = true

        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.visible = false
            // Let the fade finish before the window leaves the screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.window?.orderOut(nil) }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    /// Re-centre every time: the HUD should land on whichever screen is active.
    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame            // already excludes the menu bar
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                      y: area.maxY - size.height + Self.shadowInset - 4))
    }
}
