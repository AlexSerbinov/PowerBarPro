import Foundation

/// Parses streaming multi-line JSON output from macpow.
///
/// macpow outputs pretty-printed JSON objects separated by whitespace.
/// Each object spans multiple lines. This parser tracks brace depth
/// to detect complete objects, correctly handling strings that may
/// contain braces or escape sequences.
final class StreamingJSONParser {

    // MARK: - State

    private var buffer = ""
    private var depth = 0
    private var inString = false
    private var escape = false
    private var objectStart: String.Index?
    private var scannedCount = 0  // How many characters we've already scanned
    private let lock = NSLock()

    // MARK: - Public API

    /// Feed a chunk of text received from the pipe.
    /// Returns any complete JSON object `Data` blobs found.
    func feed(_ chunk: String) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)

        var results: [Data] = []
        // Only scan NEW characters — don't re-scan already-processed buffer
        var index = buffer.index(buffer.startIndex, offsetBy: scannedCount)

        while index < buffer.endIndex {
            let char = buffer[index]

            if escape {
                escape = false
                index = buffer.index(after: index)
                continue
            }

            if inString {
                switch char {
                case "\\":
                    escape = true
                case "\"":
                    inString = false
                default:
                    break
                }
                index = buffer.index(after: index)
                continue
            }

            // Outside a string
            switch char {
            case "\"":
                inString = true

            case "{":
                if depth == 0 {
                    objectStart = index
                }
                depth += 1

            case "}":
                depth -= 1
                if depth == 0, let start = objectStart {
                    let end = buffer.index(after: index)
                    let jsonString = String(buffer[start..<end])
                    if let data = jsonString.data(using: .utf8) {
                        results.append(data)
                    }
                    objectStart = nil
                }
                if depth < 0 {
                    depth = 0
                }

            default:
                break
            }

            index = buffer.index(after: index)
        }

        // Trim consumed data from buffer
        if let start = objectStart {
            let keepFrom = start
            buffer = String(buffer[keepFrom...])
            objectStart = buffer.startIndex
            scannedCount = buffer.count
        } else if !results.isEmpty {
            // All objects consumed — clear buffer
            buffer = ""
            scannedCount = 0
        } else {
            // No objects found, no object in progress — keep scanning position
            scannedCount = buffer.count
        }

        return results
    }

    /// Reset all parser state, discarding any buffered partial data.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer = ""
        depth = 0
        inString = false
        escape = false
        objectStart = nil
        scannedCount = 0
    }
}
