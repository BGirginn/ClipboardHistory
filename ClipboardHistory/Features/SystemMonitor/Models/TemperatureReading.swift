import Foundation

struct TemperatureReading: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let celsius: Double
}
