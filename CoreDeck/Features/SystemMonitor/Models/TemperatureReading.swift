import Foundation

struct TemperatureReading: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let celsius: Double
    let category: TemperatureSensorCategory

    init(
        id: String,
        name: String,
        celsius: Double,
        category: TemperatureSensorCategory = .cpu
    ) {
        self.id = id
        self.name = name
        self.celsius = celsius
        self.category = category
    }
}
