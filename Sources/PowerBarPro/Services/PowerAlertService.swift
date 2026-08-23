import Foundation
import Combine
import UserNotifications

/// Abstraction over the notification sink — real user notifications in
/// production, a spy in tests.
protocol AlertNotifying: AnyObject {
    func postAlert(title: String, body: String)
}

/// Posts macOS user notifications. No-ops when running outside an app
/// bundle (UNUserNotificationCenter requires one).
final class UserNotificationNotifier: AlertNotifying {

    private var authorizationRequested = false
    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    func postAlert(title: String, body: String) {
        guard hasBundle else { return }

        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        center.add(request)
    }
}

/// Watches attributed per-process power and alerts when a single app draws
/// more than the configured threshold continuously for `sustainSeconds`.
final class PowerAlertService {

    /// How long an app must stay above the threshold before alerting.
    let sustainSeconds: TimeInterval
    /// Minimum time between repeat alerts for the same app.
    let cooldownSeconds: TimeInterval

    private let notifier: AlertNotifying
    private let settings: SettingsStorage
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()

    /// App name → when it first crossed the threshold (current streak).
    private var streakStart: [String: Date] = [:]
    /// App name → when we last alerted about it.
    private var lastAlerted: [String: Date] = [:]

    init(
        notifier: AlertNotifying,
        settings: SettingsStorage,
        sustainSeconds: TimeInterval = 300,
        cooldownSeconds: TimeInterval = 1800,
        now: @escaping () -> Date = Date.init
    ) {
        self.notifier = notifier
        self.settings = settings
        self.sustainSeconds = sustainSeconds
        self.cooldownSeconds = cooldownSeconds
        self.now = now
    }

    /// Subscribe to the attributed-process stream.
    func bind(to publisher: AnyPublisher<[AttributedPower], Never>) {
        publisher
            .sink { [weak self] processes in
                self?.evaluate(processes)
            }
            .store(in: &cancellables)
    }

    /// Evaluate one sample of attributed processes. Internal for testability.
    func evaluate(_ processes: [AttributedPower]) {
        guard settings.alertsEnabled else {
            streakStart.removeAll()
            return
        }

        let threshold = Double(settings.alertThresholdW)
        let currentTime = now()
        let hot = processes.filter { $0.totalWatts >= threshold }
        let hotNames = Set(hot.map(\.name))

        // Apps that dropped below the threshold lose their streak
        streakStart = streakStart.filter { hotNames.contains($0.key) }

        for proc in hot {
            let start = streakStart[proc.name] ?? currentTime
            streakStart[proc.name] = start

            let sustained = currentTime.timeIntervalSince(start)
            guard sustained >= sustainSeconds else { continue }

            if let last = lastAlerted[proc.name],
               currentTime.timeIntervalSince(last) < cooldownSeconds {
                continue
            }

            lastAlerted[proc.name] = currentTime
            let minutes = Int(sustained / 60)
            notifier.postAlert(
                title: L.alertTitle(proc.name),
                body: L.alertBody(watts: proc.totalWatts, minutes: max(minutes, 1))
            )
        }
    }
}
