import XCTest
@testable import PowerBarPro

final class AgentSessionsServiceTests: XCTestCase {

    // pid ppid rss pcpu etime comm
    private let samplePS = """
        100 1 1000 0.5 01:00 /sbin/launchd
        200 100 512000 12.5 02:30:00 /Users/x/.local/bin/claude
        201 200 128000 1.0 02:29:00 node /Users/x/mcp-server
        202 201 64000 0.5 02:28:00 node worker
        203 202 32000 0.1 02:27:00 caffeinate
        300 100 256000 5.0 45:00 codex
        400 100 90000 2.0 10:00 /Applications/Safari.app/Contents/MacOS/Safari
        500 400 10000 0.1 09:00 com.apple.WebKit.WebContent
        """

    func testParseFindsAgentSessions() {
        let parsed = AgentSessionsService.parse(psOutput: samplePS)
        XCTAssertEqual(parsed.sessions.count, 2)

        let claude = parsed.sessions.first { $0.kind == .claude }
        XCTAssertEqual(claude?.pid, 200)
        XCTAssertEqual(claude?.rssKB, 512000)
        XCTAssertEqual(claude?.cpu ?? 0, 12.5, accuracy: 0.01)
        XCTAssertEqual(claude?.uptime, "02:30:00")

        let codex = parsed.sessions.first { $0.kind == .codex }
        XCTAssertEqual(codex?.pid, 300)
    }

    func testParseAttributesHelpersUpToThreeLevels() {
        let parsed = AgentSessionsService.parse(psOutput: samplePS)
        // 201 (child) + 202 (grandchild) + 203 (great-grandchild) of claude;
        // Safari/WebKit are unrelated and must not count.
        XCTAssertEqual(parsed.helpersKB, 128000 + 64000 + 32000)
    }

    func testParseIgnoresUnrelatedProcesses() {
        let parsed = AgentSessionsService.parse(psOutput: "1 0 100 0.0 01:00 /sbin/launchd\n")
        XCTAssertTrue(parsed.sessions.isEmpty)
        XCTAssertEqual(parsed.helpersKB, 0)
    }

    func testParseLsofMapsPidsToCwds() {
        let out = """
            p200
            fcwd
            n/Users/x/Desktop/projects/personal/PowerBarPro
            p300
            fcwd
            n/Users/x/Desktop/projects/jamal/trocador
            """
        let map = AgentSessionsService.parseLsof(out)
        XCTAssertEqual(map[200], "/Users/x/Desktop/projects/personal/PowerBarPro")
        XCTAssertEqual(map[300], "/Users/x/Desktop/projects/jamal/trocador")
    }

    func testSnapshotIntegrationWithStubbedTools() {
        let service = AgentSessionsService(
            runTool: { path, _ in
                if path.hasSuffix("ps") { return self.samplePS }
                return "p200\nfcwd\nn/Users/x/proj\np300\nfcwd\nn/Users/x/other\n"
            },
            sessionNameProvider: { pid in pid == 200 ? "my-session" : nil }
        )

        let snap = service.snapshot()
        XCTAssertEqual(snap.sessions.count, 2)
        // Sorted by memory descending: claude (500MB) first
        XCTAssertEqual(snap.sessions[0].kind, .claude)
        XCTAssertEqual(snap.sessions[0].rssMB, 500)
        XCTAssertEqual(snap.sessions[0].name, "my-session")
        XCTAssertEqual(snap.sessions[0].displayLabel, "my-session")
        XCTAssertEqual(snap.sessions[0].cwd, "/Users/x/proj")
        XCTAssertEqual(snap.sessions[1].displayLabel, "other")
        XCTAssertEqual(snap.helpersMB, (128000 + 64000 + 32000) / 1024)
    }

    func testSummaryFormatsCountsAndMemory() {
        let sessions = [
            AgentSession(kind: .claude, pid: 1, cwd: "/a", rssMB: 700, cpuPercent: 1, uptime: "01:00", name: nil),
            AgentSession(kind: .claude, pid: 2, cwd: "/b", rssMB: 300, cpuPercent: 1, uptime: "01:00", name: nil),
            AgentSession(kind: .codex, pid: 3, cwd: "/c", rssMB: 200, cpuPercent: 1, uptime: "01:00", name: nil),
        ]
        let snap = AgentSessionsSnapshot(sessions: sessions, helpersMB: 100)
        XCTAssertEqual(snap.totalMB, 1300)
        XCTAssertEqual(snap.summary, "2 Claude · 1 Codex · 1.3 GB")
    }

    func testEmptySnapshotSummary() {
        XCTAssertEqual(AgentSessionsSnapshot.empty.summary, "—")
    }
}
