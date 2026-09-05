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

    var primaryTemperatureReading: PrimaryTemperatureReading? {
        let cpuValues = temperatures
            .filter { $0.category == .cpu }
            .map(\.celsius)
        let category: TemperatureSensorCategory = cpuValues.isEmpty ? .soc : .cpu
        let values = cpuValues.isEmpty
            ? temperatures.filter { $0.category == .soc }.map(\.celsius)
            : cpuValues
        guard !values.isEmpty else { return nil }
        return PrimaryTemperatureReading(
            celsius: values.reduce(0, +) / Double(values.count),
            category: category
        )
    }

    var primaryTemperature: Double? {
        primaryTemperatureReading?.celsius
    }
}
