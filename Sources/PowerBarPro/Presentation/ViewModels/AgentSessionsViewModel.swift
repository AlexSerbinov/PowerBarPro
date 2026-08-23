import Foundation
import Combine
import AppKit

/// Presentation logic for the Claude/Codex sessions section.
/// Snapshots on demand (section expand / refresh) — no background polling.
final class AgentSessionsViewModel: ObservableObject {

    @Published private(set) var snapshot: AgentSessionsSnapshot = .empty
    @Published private(set) var isLoading = false

    private let service: AgentSessionsService

    init(service: AgentSessionsService = AgentSessionsService()) {
        self.service = service
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let snap = self.service.snapshot()
            DispatchQueue.main.async {
                self.snapshot = snap
                self.isLoading = false
            }
        }
    }

    func revealInFinder(_ session: AgentSession) {
        guard session.cwd != "?" else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.cwd)])
    }

    /// Kill with confirmation. The conversation stays on disk — resume works.
    func requestKill(_ session: AgentSession) {
        let alert = NSAlert()
        alert.messageText = L.killSessionTitle(session.displayLabel, pid: session.pid)
        alert.informativeText = L.killSessionBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.killSessionConfirm)
        alert.addButton(withTitle: L.cancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            service.kill(pid: session.pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refresh()
            }
        }
    }
}
