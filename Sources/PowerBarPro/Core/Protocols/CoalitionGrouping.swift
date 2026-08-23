import Foundation

/// Abstraction over coalition (app-level) process grouping.
protocol CoalitionGrouping {
    func group(_ processes: [ProcessPowerInfo], systemPowerW: Double) -> [CoalitionInfo]
    func clearCache()
}
