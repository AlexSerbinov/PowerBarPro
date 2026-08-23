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

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: MacFans.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
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
                self?.isBusy = false
                if let result, result.ok {
                    self?.reply = result
                } else if request.cmd == "status" {
                    self?.reply = nil
                }
            }
        }
    }
}
