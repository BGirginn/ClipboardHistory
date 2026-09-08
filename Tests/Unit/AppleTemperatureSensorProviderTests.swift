import XCTest

@testable import ClipboardHistoryTestHost

final class AppleTemperatureSensorProviderTests: XCTestCase {
    func testHIDReadingsKeepVerifiedCPUSensorsSeparateFromSoCSensors() {
        let provider = AppleTemperatureSensorProvider {
            [
                "pACC MTR Temp Sensor0": 48,
                "eACC MTR Temp Sensor0": 52,
                "PMGR SOC Die Temp Sensor0": 63,
                "gas gauge battery": 35,
                "SOC MTR Temp Sensor99": 150
            ]
        }

        let readings = provider.readings()

        XCTAssertEqual(Set(readings.map(\.id)), [
            "pACC MTR Temp Sensor0",
            "eACC MTR Temp Sensor0",
            "PMGR SOC Die Temp Sensor0"
        ])
        XCTAssertEqual(readings.filter { $0.category == .cpu }.count, 2)
        XCTAssertEqual(readings.filter { $0.category == .soc }.count, 1)
    }
}
