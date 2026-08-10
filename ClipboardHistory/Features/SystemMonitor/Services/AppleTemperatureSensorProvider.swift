import Foundation

struct AppleTemperatureSensorProvider: TemperatureSensorProviding {
    private let smc = AppleSMCTemperatureProvider()

    func readings() -> [TemperatureReading] {
        #if arch(arm64)
        let hidReadings = CHAppleSiliconTemperatureSensors().compactMap { key, value -> TemperatureReading? in
            let celsius = value.doubleValue
            guard (10...130).contains(celsius) else { return nil }
            return TemperatureReading(
                id: key,
                name: sensorName(key),
                celsius: celsius
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !hidReadings.isEmpty { return hidReadings }
        #endif
        return smc.readings()
    }

    private func sensorName(_ key: String) -> String {
        if key.hasPrefix("pACC") { return String(localized: "Performance CPU") + " · " + key }
        if key.hasPrefix("eACC") { return String(localized: "Efficiency CPU") + " · " + key }
        if key.hasPrefix("PMU") { return String(localized: "SoC Die") + " · " + key }
        return String(localized: "SoC") + " · " + key
    }
}
