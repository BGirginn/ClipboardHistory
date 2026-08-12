import Foundation

enum RateMetricUnit: String, Codable, CaseIterable, Identifiable {
    case automatic
    case kilobytes
    case megabytes
    case gigabytes
    var id: String { rawValue }
}
