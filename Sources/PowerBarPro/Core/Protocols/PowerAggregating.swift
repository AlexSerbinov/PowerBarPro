import Foundation

/// Abstraction over power history and averaging.
/// Implementations: `PowerAggregator` (production), direct injection in tests.
protocol PowerAggregating: AnyObject {
    func record(_ reading: PowerReading)
    func reset()
    func readings(for seconds: Int) -> [PowerReading]
    func average(for seconds: Int) -> (allPower: Double, sysPower: Double)?
    func resolvedPower(for mode: DisplayMode, instant: SystemMetrics?) -> Double?
    var readingCount: Int { get }
}
