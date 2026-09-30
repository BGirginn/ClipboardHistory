import Foundation

struct PrimaryTemperatureReading: Equatable, Sendable {
    let celsius: Double
    let category: TemperatureSensorCategory

    var localizedSourceName: String {
        switch category {
        case .cpu: String(localized: "CPU")
        case .soc: String(localized: "SoC Die")
        }
    }
}
