import Foundation
import AppKit
import Darwin

// Client for the MacFans root daemon (github: mac-fans project on this
// machine). The daemon owns the AppleSMC connection and serves a unix
// socket at /var/run/macfans.sock (root:staff 0660) — so PowerBarPro can
// switch fan modes without privileges or subprocess spawns.
//
// Protocol types mirror MacFansCore/Protocol.swift (JSON line per message).

enum MacFans {

    static let socketPath = "/var/run/macfans.sock"

    /// Posted by the macfans CLI after every change (fn+6...9 via Karabiner).
    static let didChangeNotification = Notification.Name("com.serbinov.macfans.changed")

    enum Mode: String, Codable {
        case auto      // macOS owns the fans
        case manual    // fixed percentage
        case curve     // percentage tracks battery temperature
    }

    struct Curve: Codable, Equatable {
        var lowTemp: Double
        var lowPct: Int
        var highTemp: Double
        var highPct: Int
    }

    struct Request: Codable {
        var cmd: String            // "status" | "set" | "setCurve"
        var mode: Mode?
        var pct: Int?
        var curve: Curve?

        static let status = Request(cmd: "status")
        static let auto = Request(cmd: "set", mode: .auto)
        static let curveMode = Request(cmd: "set", mode: .curve)
        static func manual(_ pct: Int) -> Request { Request(cmd: "set", mode: .manual, pct: pct) }
        static func setCurve(_ curve: Curve) -> Request { Request(cmd: "setCurve", curve: curve) }
    }

    /// One colour per MODE — shared by the menu bar fan line, the HUD and
    /// the popover chips, so a glance at any of them answers "what mode am
    /// I in". Fill/level always shows how hard the fans actually work.
    /// Auto is the resting state: neutral gray. No red anywhere by design.
    static func modeTint(mode: Mode, pct: Int) -> NSColor {
        switch mode {
        case .auto: return .secondaryLabelColor
        case .curve: return .systemPurple
        case .manual:
            if pct >= 85 { return .systemOrange }
            return pct >= 50 ? .systemBlue : .systemGreen
        }
    }

    struct FanReport: Codable {
        var index: Int
        var rpm: Int
        var target: Int
        var min: Int
        var max: Int
    }

    struct Reply: Codable {
        var ok: Bool
        var mode: Mode
        var pct: Int
        var fans: [FanReport]
        var tempC: Double?
        var batteryC: Double?
        var curve: Curve
        var error: String?

        var rpmText: String {
            let fastest = fans.map(\.rpm).max() ?? 0
            return fastest >= 1000 ? String(format: "%.1fk", Double(fastest) / 1000) : "\(fastest)"
        }

        var modeTitle: String {
            switch mode {
            case .auto: return "Auto"
            case .curve: return "Curve"
            case .manual: return "\(pct)%"
            }
        }
    }

    enum ClientError: Error {
        case unavailable
        case io
        case badReply
    }

    /// True when the daemon's socket exists — cheap availability probe.
    static var daemonInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    /// One-shot request/response against the daemon. Blocking — call off main.
    static func send(_ request: Request, timeout: TimeInterval = 2) throws -> Reply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.io }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() where i < raw.count - 1 { raw[i] = b }
            raw[min(bytes.count, raw.count - 1)] = 0
        }

        let rc = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.connect(fd, sp, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw ClientError.unavailable }

        var payload = Array(try JSONEncoder().encode(request))
        payload.append(0x0A)
        var sent = 0
        try payload.withUnsafeBytes { raw in
            while sent < payload.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), payload.count - sent)
                if n <= 0 {
                    if errno == EINTR { continue }
                    throw ClientError.io
                }
                sent += n
            }
        }

        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        while out.count < 1 << 20 {
            let n = read(fd, &buf, buf.count)
            if n < 0 {
                if errno == EINTR { continue }
                throw ClientError.io
            }
            if n == 0 { break }
            if let nl = buf[0..<n].firstIndex(of: 0x0A) {
                out.append(contentsOf: buf[0..<nl])
                break
            }
            out.append(contentsOf: buf[0..<n])
        }
        guard !out.isEmpty else { throw ClientError.badReply }
        return try JSONDecoder().decode(Reply.self, from: Data(out))
    }
}
