import Foundation
import IOKit.pwr_mgt
import Combine

/// Keeps the Mac awake — the Amphetamine feature.
///
/// No cursor-wiggling hacks: a proper IOKit power assertion
/// (`PreventUserIdleDisplaySleep`, same as `caffeinate -d` and Amphetamine
/// itself) tells macOS the display and system must not idle-sleep. The
/// assertion dies with the process, so a crash can never leave the machine
/// insomniac.
final class KeepAwakeService: ObservableObject {

    /// Injectable assertion backend for tests.
    struct AssertionBackend {
        var create: (String) -> IOPMAssertionID?
        var release: (IOPMAssertionID) -> Void

        static let live = AssertionBackend(
            create: { reason in
                var id = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason as CFString,
                    &id
                )
                return result == kIOReturnSuccess ? id : nil
            },
            release: { id in
                IOPMAssertionRelease(id)
            }
        )
    }

    @Published private(set) var isActive = false
    /// When the current session auto-expires; nil while inactive or endless.
    @Published private(set) var endsAt: Date?

    private let backend: AssertionBackend
    private var assertionID: IOPMAssertionID?
    private var expiryTimer: Timer?

    init(backend: AssertionBackend = .live) {
        self.backend = backend
    }

    deinit {
        expiryTimer?.invalidate()
        if let id = assertionID { backend.release(id) }
    }

    // MARK: - Public

    /// Start (or restart) a keep-awake session.
    /// - Parameter duration: seconds until auto-off; nil = until turned off.
    func start(duration: TimeInterval?) {
        stop()

        guard let id = backend.create("PowerBarPro Keep Awake") else { return }
        assertionID = id
        isActive = true

        if let duration {
            endsAt = Date().addingTimeInterval(duration)
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
            timer.tolerance = min(30, duration / 20)
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        } else {
            endsAt = nil
        }
    }

    func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        if let id = assertionID {
            backend.release(id)
            assertionID = nil
        }
        isActive = false
        endsAt = nil
    }
}
