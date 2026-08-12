import XCTest

@testable import ClipboardHistory

private actor SystemMetricsProviderStub: SystemMetricsProviding {
    private var index = 0
    private(set) var scope: NetworkInterfaceScope?
    private(set) var resetCount = 0

    func sample(at date: Date) async -> SystemMetricSnapshot {
        index += 1
        return SystemMetricSnapshot(
            timestamp: date,
            cpu: CPUUsageSnapshot(
                totalPercent: Double(index),
                userPercent: Double(index),
                systemPercent: 0,
                idlePercent: 100 - Double(index),
                perCorePercent: [Double(index)]
            ),
            memory: MemoryUsageSnapshot(
                totalBytes: 1_000,
                usedBytes: 500,
                activeBytes: 200,
                inactiveBytes: 100,
                wiredBytes: 100,
                compressedBytes: 100,
                cachedBytes: 100,
                freeBytes: 400,
                pressure: .normal
            ),
            network: NetworkRateSnapshot(
                receivedBytesPerSecond: 1_024,
                sentBytesPerSecond: 2_048,
                interfaceName: "en0"
            ),
            disk: DiskRateSnapshot(readBytesPerSecond: 4_096, writtenBytesPerSecond: 8_192),
            temperatures: [TemperatureReading(id: "Tp01", name: "CPU Tp01", celsius: 54)],
            thermalState: .nominal
        )
    }

    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) {
        self.scope = scope
    }

    func resetBaselines() {
        resetCount += 1
    }
}

private actor EmptyTemperatureMetricsProvider: SystemMetricsProviding {
    func sample(at date: Date) -> SystemMetricSnapshot {
        var snapshot = SystemMetricSnapshot.empty
        snapshot.timestamp = date
        return snapshot
    }
}

@MainActor
final class SystemMetricsControllerTests: XCTestCase {
    func testRefreshPublishesCompleteNumericSnapshotAndFormatsMenuBarValues() async {
        let controller = SystemMetricsController(provider: SystemMetricsProviderStub())

        await controller.refreshNow()
        controller.refresh()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(controller.snapshot.cpu.totalPercent, 2)
        XCTAssertEqual(controller.snapshot.memory.usedPercent, 50)
        XCTAssertEqual(controller.snapshot.primaryTemperature, 54)
        XCTAssertEqual(controller.value(for: .cpu), "2%")
        XCTAssertEqual(controller.value(for: .memory), "50%")
        XCTAssertEqual(controller.value(for: .temperature), "54°C")
        XCTAssertNil(controller.errorMessage)
    }

    func testHistoryIsBoundedAndSamplingStopsWithoutConsumers() async {
        let controller = SystemMetricsController(
            provider: SystemMetricsProviderStub(),
            maximumHistoryCount: 3
        )
        for _ in 0..<5 { await controller.refreshNow() }
        XCTAssertEqual(controller.history.map(\.cpu.totalPercent), [3, 4, 5])

        controller.setDemand(.menuBar, active: true)
        XCTAssertTrue(controller.hasActiveSampling)
        controller.setDemand(.menuBar, active: false)
        XCTAssertFalse(controller.hasActiveSampling)
    }

    func testLiveProviderReturnsSafeRangesOnCurrentMac() async {
        let provider = SystemMetricsProvider()
        _ = await provider.sample(at: .now)
        try? await Task.sleep(for: .milliseconds(20))
        let snapshot = await provider.sample(at: .now)

        XCTAssertTrue((0...100).contains(snapshot.cpu.totalPercent))
        XCTAssertLessThanOrEqual(snapshot.memory.usedBytes, snapshot.memory.totalBytes)
        XCTAssertGreaterThanOrEqual(snapshot.network.receivedBytesPerSecond, 0)
        XCTAssertGreaterThanOrEqual(snapshot.disk.readBytesPerSecond, 0)
        XCTAssertTrue(snapshot.temperatures.allSatisfy { (10...130).contains($0.celsius) })
    }

    func testAllMetricFormatsScopeAndStatisticsAreDeterministic() async {
        let suite = "SystemMetricsFormats-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let provider = SystemMetricsProviderStub()
        let controller = SystemMetricsController(provider: provider, defaults: defaults)
        await controller.refreshNow()
        await controller.refreshNow()

        XCTAssertEqual(controller.value(for: .cpu), "2%")
        XCTAssertTrue(
            controller.value(
                for: .memory,
                formats: MetricFormatPreferences(
                    memory: .usedAndTotal,
                    temperature: .celsius,
                    rate: .automatic
                )
            ).contains("/")
        )
        XCTAssertEqual(
            controller.value(
                for: .temperature,
                formats: MetricFormatPreferences(
                    memory: .percentage,
                    temperature: .fahrenheit,
                    rate: .automatic
                )
            ),
            "129°F"
        )
        XCTAssertTrue(controller.value(for: .networkDownload).hasSuffix("/s"))
        XCTAssertTrue(controller.value(for: .networkUpload).hasSuffix("/s"))
        XCTAssertTrue(controller.value(for: .diskRead).hasSuffix("/s"))
        XCTAssertTrue(controller.value(for: .diskWrite).hasSuffix("/s"))

        for unit in [RateMetricUnit.kilobytes, .megabytes, .gigabytes] {
            let value = controller.value(
                for: .networkDownload,
                formats: MetricFormatPreferences(
                    memory: .percentage,
                    temperature: .celsius,
                    rate: unit
                )
            )
            XCTAssertTrue(value.hasSuffix(unit == .kilobytes ? "KB/s" : unit == .megabytes ? "MB/s" : "GB/s"))
        }

        let statistics = controller.temperatureStatistics(for: "Tp01")
        XCTAssertEqual(statistics?.minimum, 54)
        XCTAssertEqual(statistics?.average, 54)
        XCTAssertEqual(statistics?.maximum, 54)
        XCTAssertNil(controller.temperatureStatistics(for: "missing"))

        controller.setNetworkInterfaceScope(.allPhysical)
        try? await Task.sleep(for: .milliseconds(30))
        let selectedScope = await provider.scope
        XCTAssertEqual(selectedScope, .allPhysical)
        XCTAssertEqual(controller.networkInterfaceScope, .allPhysical)

        for demand in [SystemMetricsDemand.controlCenter, .menuBar, .detail] {
            controller.setDemand(demand, active: true)
            XCTAssertTrue(controller.hasActiveSampling)
            controller.setDemand(demand, active: false)
        }
        controller.stop()
        XCTAssertFalse(controller.hasActiveSampling)
    }

    func testUnavailableTemperatureReportsErrorAndDash() async {
        let controller = SystemMetricsController(provider: EmptyTemperatureMetricsProvider())
        await controller.refreshNow()

        XCTAssertEqual(controller.value(for: .temperature), "—")
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertNil(controller.temperatureStatistics(for: "missing"))
    }
}
