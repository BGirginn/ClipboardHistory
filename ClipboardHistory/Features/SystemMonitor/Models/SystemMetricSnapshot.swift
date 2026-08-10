import Foundation

struct SystemMetricSnapshot: Equatable, Sendable {
    var timestamp: Date
    var cpu: CPUUsageSnapshot
    var memory: MemoryUsageSnapshot
    var network: NetworkRateSnapshot
    var disk: DiskRateSnapshot
    var temperatures: [TemperatureReading]
    var thermalState: ProcessInfo.ThermalState

    static let empty = SystemMetricSnapshot(
        timestamp: .now,
        cpu: .empty,
        memory: .empty,
        network: .empty,
        disk: .empty,
        temperatures: [],
        thermalState: .nominal
    )

    var primaryTemperature: Double? {
        temperatures.map(\.celsius).max()
    }
}
