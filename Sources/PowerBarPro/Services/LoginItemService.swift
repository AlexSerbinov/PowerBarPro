import Foundation
import ServiceManagement

/// Wraps SMAppService (macOS 13+) for the "launch at login" toggle.
/// Registration only works from an installed .app bundle; from a bare
/// binary the calls throw and the state simply stays off.
final class LoginItemService: ObservableObject {

    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Bare-binary run or user declined — reflect the real state below.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
