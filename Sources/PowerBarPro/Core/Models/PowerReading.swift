import Foundation

/// A single timestamped power sample stored in the rolling history buffer.
struct PowerReading: Identifiable, Sendable, Codable {
    let id: UUID
    let allPower: Double
    let sysPower: Double
    let timestamp: Date

    init(allPower: Double, sysPower: Double, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.allPower = allPower
        self.sysPower = sysPower
        self.timestamp = timestamp
    }

    // MARK: - Codable (persistence)

    /// `id` is runtime-only — serializing a UUID string per sample would
    /// triple the size of the 6-hour history file written every few minutes.
    private enum CodingKeys: String, CodingKey {
        case allPower = "a"
        case sysPower = "s"
        case timestamp = "t"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.allPower = try container.decode(Double.self, forKey: .allPower)
        self.sysPower = try container.decode(Double.self, forKey: .sysPower)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}
