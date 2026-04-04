import Foundation

/// Reads battery hardware data from macOS `ioreg` and performs
/// remaining-time calculations.
final class SystemBatteryService: BatteryMonitoring {

    private let processRunner: ProcessRunning

    init(processRunner: ProcessRunning) {
        self.processRunner = processRunner
    }

    // MARK: - BatteryMonitoring

    func getBatteryState() -> BatteryState? {
        let data: Data
        do {
            data = try processRunner.runSync(
                executablePath: Constants.Battery.ioregPath,
                arguments: ["-a", "-r", "-n", "AppleSmartBattery"]
            )
        } catch {
            return nil
        }

        return parseBatteryData(data)
    }

    func calculateRemainingTime(battery: BatteryState, averagePowerW: Double) -> TimeInterval? {
        guard battery.isOnBatteryPower else { return nil }
        guard averagePowerW > Constants.Battery.minimumReliablePowerW else { return nil }

        let hours = battery.remainingEnergyWh / averagePowerW
        guard hours.isFinite && hours > 0 else { return nil }

        return hours * 3600
    }

    // MARK: - Private

    private func parseBatteryData(_ data: Data) -> BatteryState? {
        do {
            guard let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [[String: Any]] else {
                return nil
            }

            guard let dict = plist.first else { return nil }

            let isCharging = dict["IsCharging"] as? Bool ?? false
            let externalConnected = dict["ExternalConnected"] as? Bool ?? false
            let currentCapacity = dict["AppleRawCurrentCapacity"] as? Int ?? 0
            let voltage = dict["Voltage"] as? Int ?? 0

            guard currentCapacity > 0, voltage > 0 else { return nil }

            return BatteryState(
                isCharging: isCharging,
                externalConnected: externalConnected,
                currentCapacity: currentCapacity,
                voltage: voltage
            )
        } catch {
            return nil
        }
    }
}
