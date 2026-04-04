import Foundation

/// Snapshot of battery hardware state from ioreg.
struct BatteryState: Equatable, Sendable {
    let isCharging: Bool
    let externalConnected: Bool
    let currentCapacity: Int   // mAh
    let voltage: Int           // mV

    /// Remaining energy in Watt-hours: (mAh → Ah) * (mV → V).
    var remainingEnergyWh: Double {
        (Double(currentCapacity) / 1000.0) * (Double(voltage) / 1000.0)
    }

    /// True when running on battery (no external power source).
    var isOnBatteryPower: Bool {
        !externalConnected
    }
}
