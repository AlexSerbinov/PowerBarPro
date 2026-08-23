import Foundation
import Combine
@testable import PowerBarPro

/// Mock power monitor for testing. Allows injecting metrics, errors, and running state.
final class MockPowerMonitor: PowerMonitoring {

    private let metricsSubject = CurrentValueSubject<SystemMetrics?, Never>(nil)
    private let errorSubject = CurrentValueSubject<AppError?, Never>(nil)
    private let isRunningSubject = CurrentValueSubject<Bool, Never>(false)

    var metricsPublisher: AnyPublisher<SystemMetrics?, Never> {
        metricsSubject.eraseToAnyPublisher()
    }
    var errorPublisher: AnyPublisher<AppError?, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    var isRunningPublisher: AnyPublisher<Bool, Never> {
        isRunningSubject.eraseToAnyPublisher()
    }

    // MARK: - Call tracking

    private(set) var startMonitoringCallCount = 0
    private(set) var stopMonitoringCallCount = 0
    private(set) var lastSetInterval: Int?

    // MARK: - PowerMonitoring

    func startMonitoring() {
        startMonitoringCallCount += 1
        isRunningSubject.send(true)
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        isRunningSubject.send(false)
        metricsSubject.send(nil)
    }

    func setUpdateInterval(_ intervalMs: Int) {
        lastSetInterval = intervalMs
    }

    // MARK: - Test Helpers

    func emit(_ metrics: SystemMetrics) {
        metricsSubject.send(metrics)
    }

    func emitError(_ error: AppError) {
        errorSubject.send(error)
    }

    func clearError() {
        errorSubject.send(nil)
    }
}
