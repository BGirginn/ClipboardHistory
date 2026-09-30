import Foundation

protocol TemperatureSensorProviding: Sendable {
    func readings() -> [TemperatureReading]
}
