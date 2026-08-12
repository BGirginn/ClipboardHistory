import Foundation

struct MetricFormatPreferences: Codable, Equatable {
    var memory: MemoryMetricFormat
    var temperature: TemperatureMetricUnit
    var rate: RateMetricUnit

    static let defaults = MetricFormatPreferences(
        memory: .percentage,
        temperature: .celsius,
        rate: .automatic
    )
}
