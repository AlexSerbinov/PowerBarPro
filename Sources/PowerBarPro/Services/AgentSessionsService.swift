import Foundation

// MARK: - Agent Session Model

/// CLI coding agents we can detect. Raw value == process basename.
enum AgentKind: String, CaseIterable, Sendable {
    case claude = "claude"
    case codex = "codex"

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct AgentSession: Identifiable, Sendable {
    let kind: AgentKind
    let pid: Int32
    let cwd: String
    let rssMB: Int
    let cpuPercent: Double
    let uptime: String
    /// User-assigned session name (Claude Code /rename), when available.
    let name: String?

    var id: Int32 { pid }

    /// Row label: session name if set, otherwise the project folder name.
    var displayLabel: String {
        if let name, !name.isEmpty { return name }
        return projectName
    }

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    /// Path shortened for display: ~/Desktop/projects/jamal/trocador → jamal/trocador
    var shortPath: String {
        let home = NSHomeDirectory()
        let projectsPrefix = home + "/Desktop/projects/"
        if cwd.hasPrefix(projectsPrefix) {
            return String(cwd.dropFirst(projectsPrefix.count))
        }
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }
}

// MARK: - Snapshot

struct AgentSessionsSnapshot: Sendable {
    let sessions: [AgentSession]
    /// MCP servers & other child processes attributed to the sessions (MB).
    let helpersMB: Int

    static let empty = AgentSessionsSnapshot(sessions: [], helpersMB: 0)

    var totalSessionsMB: Int { sessions.reduce(0) { $0 + $1.rssMB } }
    var totalMB: Int { totalSessionsMB + helpersMB }

    func sessions(of kind: AgentKind) -> [AgentSession] {
        sessions.filter { $0.kind == kind }
    }

    /// Compact one-line summary, e.g. "3 Claude · 1 Codex · 2.1 GB".
    var summary: String {
        guard !sessions.isEmpty else { return "—" }
        let gb = Double(totalMB) / 1024.0
        let mem = gb >= 1.0 ? String(format: "%.1f GB", gb) : "\(totalMB) MB"
        var parts: [String] = []
        let nClaude = sessions(of: .claude).count
        let nCodex = sessions(of: .codex).count
        if nClaude > 0 { parts.append("\(nClaude) Claude") }
        if nCodex > 0 { parts.append("\(nCodex) Codex") }
        return parts.joined(separator: " · ") + " · " + mem
    }
}

// MARK: - Service

/// Finds running Claude Code / Codex CLI sessions and reports per-session
/// resource usage. Snapshots are taken on demand — no background polling.
/// Cost per snapshot: one `ps` + one `lsof` (~50–150 ms) — call off main.
final class AgentSessionsService {

    /// Injectable external-tool runner: (executablePath, args) → stdout.
    typealias ToolRunner = (String, [String]) -> String

    private let runTool: ToolRunner
    private let sessionNameProvider: (Int32) -> String?

    init(
        runTool: ToolRunner? = nil,
        sessionNameProvider: ((Int32) -> String?)? = nil
    ) {
        self.runTool = runTool ?? Self.defaultToolRunner
        self.sessionNameProvider = sessionNameProvider ?? Self.claudeSessionName
    }

    // MARK: - Public

    func snapshot() -> AgentSessionsSnapshot {
        let psOutput = runTool("/bin/ps", ["-Ao", "pid=,ppid=,rss=,pcpu=,etime=,comm="])
        let parsed = Self.parse(psOutput: psOutput)

        let cwds = workingDirectories(for: parsed.sessions.map(\.pid))

        let sessions = parsed.sessions.map { s in
            AgentSession(
                kind: s.kind,
                pid: s.pid,
                cwd: cwds[s.pid] ?? "?",
                rssMB: s.rssKB / 1024,
                cpuPercent: s.cpu,
                uptime: s.uptime,
                name: s.kind == .claude ? sessionNameProvider(s.pid) : nil
            )
        }.sorted { $0.rssMB > $1.rssMB }

        return AgentSessionsSnapshot(sessions: sessions, helpersMB: parsed.helpersKB / 1024)
    }

    func kill(pid: Int32) {
        Darwin.kill(pid, SIGTERM)
    }

    // MARK: - Parsing (pure, testable)

    struct ParsedProcessTable {
        struct Row {
            let pid: Int32
            let kind: AgentKind
            let rssKB: Int
            let cpu: Double
            let uptime: String
        }
        let sessions: [Row]
        let helpersKB: Int
    }

    /// Parse `ps -Ao pid=,ppid=,rss=,pcpu=,etime=,comm=` output: find agent
    /// sessions and attribute descendants (MCP servers spawned via `npm exec`,
    /// their node children, caffeinate, etc. — up to 3 ancestor levels) to a
    /// "helpers" memory bucket.
    static func parse(psOutput: String) -> ParsedProcessTable {
        var sessions: [ParsedProcessTable.Row] = []
        var parentOf: [Int32: Int32] = [:]
        var rssOf: [Int32: Int] = [:]

        for line in psOutput.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 6,
                  let pid = Int32(cols[0]),
                  let ppid = Int32(cols[1]),
                  let rss = Int(cols[2]),
                  let cpu = Double(cols[3]) else { continue }
            let uptime = String(cols[4])
            let comm = cols[5...].joined(separator: " ")
            parentOf[pid] = ppid
            rssOf[pid] = rss

            // Agent CLIs run as processes whose command basename is exactly the agent name
            let base = (comm as NSString).lastPathComponent
            if let kind = AgentKind(rawValue: base) {
                sessions.append(.init(pid: pid, kind: kind, rssKB: rss, cpu: cpu, uptime: uptime))
            }
        }

        let sessionPIDs = Set(sessions.map(\.pid))
        var helpersKB = 0
        for (pid, rss) in rssOf where !sessionPIDs.contains(pid) {
            var cursor = pid
            for _ in 0..<3 {
                guard let pp = parentOf[cursor] else { break }
                if sessionPIDs.contains(pp) {
                    helpersKB += rss
                    break
                }
                cursor = pp
            }
        }

        return ParsedProcessTable(sessions: sessions, helpersKB: helpersKB)
    }

    /// Parse `lsof -Fpn` machine output into pid → cwd.
    static func parseLsof(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
            } else if line.hasPrefix("n"), let pid = currentPID {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    // MARK: - Private

    /// One `lsof` call for all PIDs: `-Fn` machine format, `-d cwd` only.
    private func workingDirectories(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let out = runTool("/usr/sbin/lsof", ["-a", "-p", list, "-d", "cwd", "-Fpn"])
        return Self.parseLsof(out)
    }

    /// Claude Code maintains ~/.claude/sessions/<PID>.json with live session
    /// metadata, including the /rename name. Returns nil if absent or unnamed.
    private static func claudeSessionName(forPID pid: Int32) -> String? {
        let path = NSHomeDirectory() + "/.claude/sessions/\(pid).json"
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String,
              !name.isEmpty else { return nil }
        return name
    }

    private static func defaultToolRunner(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
