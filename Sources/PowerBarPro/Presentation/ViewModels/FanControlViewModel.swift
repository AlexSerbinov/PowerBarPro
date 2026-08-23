import Foundation
import Combine

/// Fan control via the MacFans daemon. No polling: status refreshes on
/// section expand, after every command, and on the CLI's distributed
/// notification (fn+6...9 through Karabiner).
final class FanControlViewModel: ObservableObject {

    @Published private(set) var reply: MacFans.Reply?
    @Published private(set) var isBusy = false

    /// Daemon installed on this machine (socket exists).
    var isAvailable: Bool { MacFans.daemonInstalled }

    private var observer: NSObjectProtocol?
    private let hud = FanHUDController()
    /// What the HUD last reported — a repeat is not a change.
    private var shownState: (mode: MacFans.Mode, pct: Int)?

    init() {
        // fn+6/7/8/9 via Karabiner → macfans CLI → this notification.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: MacFans.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        // Seed state quietly so the first external keypress shows a HUD
        // with correct "was it a change" logic.
        refresh()
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func refresh() {
        guard isAvailable else { return }
        perform(.status)
    }

    func setAuto() { perform(.auto) }
    func setCurve() { perform(.curveMode) }
    func setManual(_ pct: Int) { perform(.manual(pct)) }

    // MARK: - Private

    private func perform(_ request: MacFans.Request) {
        guard !isBusy else { return }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = try? MacFans.send(request)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                if let result, result.ok {
                    self.reply = result
                    self.maybeShowHUD(result, isCommand: request.cmd != "status")
                } else if request.cmd == "status" {
                    self.reply = nil
                }
            }
        }
    }

    /// Commands always flash the HUD; status refreshes only when the mode
    /// actually changed (i.e. someone pressed fn+6...9 outside the app).
    /// The very first reading only seeds the state.
    private func maybeShowHUD(_ reply: MacFans.Reply, isCommand: Bool) {
        let now = (mode: reply.mode, pct: reply.pct)
        defer { shownState = now }

        if isCommand {
            hud.show(reply)
            return
        }
        guard let was = shownState else { return }
        if was.mode != now.mode || (now.mode != .auto && was.pct != now.pct) {
            hud.show(reply)
        }
    }
}
