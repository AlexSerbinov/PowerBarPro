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
}
