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

    /// Kill immediately, no confirmation — SIGTERM is graceful and the
    /// conversation stays on disk (`claude --resume` / `codex resume`).
    func kill(_ session: AgentSession) {
        service.kill(pid: session.pid)
        // Optimistically drop the row; a real snapshot follows shortly
        snapshot = AgentSessionsSnapshot(
            sessions: snapshot.sessions.filter { $0.pid != session.pid },
            helpersMB: snapshot.helpersMB
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }
}
