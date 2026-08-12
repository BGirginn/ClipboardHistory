import Foundation

enum TemperatureMetricUnit: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit
    var id: String { rawValue }
}
