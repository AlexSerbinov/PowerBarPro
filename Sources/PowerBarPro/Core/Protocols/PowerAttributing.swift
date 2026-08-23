import Foundation

/// Abstraction over power attribution engine.
protocol PowerAttributing: AnyObject {
    var globalCoefficient: Double { get set }
    var appCoefficients: [String: Double] { get set }
    func attribute(processes: [ProcessUsageData], budget: ComponentPowerBudget) -> [AttributedPower]
    func attribute(processInfos: [ProcessPowerInfo], metrics: SystemMetrics) -> [AttributedPower]
    func averageCorrectionFactor(attributed: [AttributedPower]) -> Double
}
