import Foundation

/// Abstraction over power history and averaging.
/// Implementations: `PowerAggregator` (production), direct injection in tests.
protocol PowerAggregating: AnyObject {
    func record(_ reading: PowerReading)
    func reset()
    /// Merge persisted readings (from a previous run) into the buffer.
    func restore(_ readings: [PowerReading])
    func readings(for seconds: Int) -> [PowerReading]
    func average(for seconds: Int) -> (allPower: Double, sysPower: Double)?
    func resolvedPower(for mode: DisplayMode, instant: SystemMetrics?) -> Double?
    var readingCount: Int { get }
}
