import Foundation

struct AppleTemperatureSensorProvider: TemperatureSensorProviding {
    private let smc = AppleSMCTemperatureProvider()
    private let hidReadingSource: @Sendable () -> [String: NSNumber]

    init(
        hidReadingSource: @escaping @Sendable () -> [String: NSNumber] = {
            CHAppleSiliconTemperatureSensors()
        }
    ) {
        self.hidReadingSource = hidReadingSource
    }

    func readings() -> [TemperatureReading] {
        #if arch(arm64)
        let hidReadings = hidReadingSource().compactMap { key, value -> TemperatureReading? in
            let celsius = value.doubleValue
            guard isVerifiedCPUOrSoCSensor(key),
                  (10...130).contains(celsius) else { return nil }
            return TemperatureReading(
                id: key,
                name: sensorName(key),
                celsius: celsius,
                category: sensorCategory(key)
            )
        }.sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame
                ? $0.id < $1.id
                : nameOrder == .orderedAscending
        }
        if !hidReadings.isEmpty { return hidReadings }
        #endif
        return smc.readings()
    }

    private func sensorName(_ key: String) -> String {
        if key.hasPrefix("pACC") { return String(localized: "Performance CPU") + " · " + key }
        if key.hasPrefix("eACC") { return String(localized: "Efficiency CPU") + " · " + key }
        if key.hasPrefix("PMU") || key.hasPrefix("PMGR") {
            return String(localized: "SoC Die") + " · " + key
        }
        return String(localized: "SoC") + " · " + key
    }

    private func sensorCategory(_ key: String) -> TemperatureSensorCategory {
        key.hasPrefix("pACC") || key.hasPrefix("eACC") ? .cpu : .soc
    }

    private func isVerifiedCPUOrSoCSensor(_ key: String) -> Bool {
        key.hasPrefix("pACC MTR Temp")
            || key.hasPrefix("eACC MTR Temp")
            || key.hasPrefix("SOC MTR Temp")
            || key.hasPrefix("PMGR SOC Die Temp")
            || (key.hasPrefix("PMU") && key.contains(" tdie"))
    }
}
