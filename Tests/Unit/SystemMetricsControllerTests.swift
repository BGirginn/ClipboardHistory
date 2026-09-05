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
                idlePercent: 100 - Double(index)
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
        XCTAssertEqual(
            controller.value(for: .temperature),
            54.0.formatted(.number.precision(.fractionLength(1))) + "°C"
        )
        XCTAssertEqual(controller.snapshot.primaryTemperatureReading?.category, .cpu)
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

    func testIndependentDemandSourcesCannotDisableEachOther() {
        let controller = SystemMetricsController(provider: SystemMetricsProviderStub())
        let popover = SamplingDemandSource()
        let window = SamplingDemandSource()

        controller.setDemand(.detail, for: popover)
        controller.setDemand(.controlCenter, for: window)
        XCTAssertEqual(controller.demandCount, 2)

        controller.setDemand(nil, for: popover)
        XCTAssertTrue(controller.hasActiveSampling)
        XCTAssertEqual(controller.demandCount, 1)

        controller.setDemand(nil, for: window)
        XCTAssertFalse(controller.hasActiveSampling)
    }

    func testMemoryFormulaAndUInt64CounterRatesHandleLargeValuesAndResets() {
        XCTAssertEqual(
            SystemMetricsProvider.usedMemoryBytes(
                total: 16_000,
                internalBytes: 9_000,
                purgeableBytes: 2_000,
                wiredBytes: 2_500,
                compressedBytes: 1_500
            ),
            11_000
        )
        XCTAssertEqual(
            SystemMetricsProvider.rate(
                current: 6_000_000_000,
                previous: 4_000_000_000,
                interval: 2
            ),
            1_000_000_000
        )
        XCTAssertEqual(SystemMetricsProvider.rate(current: 3, previous: 4, interval: 1), 0)
    }

    func testLiveProviderReturnsSafeRangesOnCurrentMac() async {
        let provider = SystemMetricsProvider()
        _ = await provider.sample(at: .now)
        try? await Task.sleep(for: .milliseconds(20))
        let snapshot = await provider.sample(at: .now)

        XCTAssertTrue((0...100).contains(snapshot.cpu.totalPercent))
        XCTAssertEqual(
            snapshot.cpu.totalPercent,
            snapshot.cpu.userPercent + snapshot.cpu.systemPercent,
            accuracy: 0.01
        )
        XCTAssertEqual(
            snapshot.cpu.totalPercent + snapshot.cpu.idlePercent,
            100,
            accuracy: 0.01
        )
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
            129.2.formatted(.number.precision(.fractionLength(1))) + "°F"
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
        XCTAssertEqual(controller.value(for: .networkDownload), "0 B/s")
        XCTAssertEqual(controller.value(for: .networkUpload), "0 B/s")
        XCTAssertEqual(controller.value(for: .diskRead), "0 B/s")
        XCTAssertEqual(controller.value(for: .diskWrite), "0 B/s")
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertNil(controller.temperatureStatistics(for: "missing"))
    }

    func testPrimaryTemperatureAveragesCPUCoresInsteadOfFreezingOnHottestSensor() {
        var snapshot = SystemMetricSnapshot.empty
        snapshot.temperatures = [
            TemperatureReading(id: "cpu-1", name: "CPU 1", celsius: 48),
            TemperatureReading(id: "cpu-2", name: "CPU 2", celsius: 52),
            TemperatureReading(
                id: "soc",
                name: "SoC",
                celsius: 70,
                category: .soc
            )
        ]

        XCTAssertEqual(snapshot.primaryTemperature, 50)
        XCTAssertEqual(snapshot.primaryTemperatureReading?.category, .cpu)
    }

    func testPrimaryTemperatureUsesSoCAverageWhenCPUSensorsAreUnavailable() {
        var snapshot = SystemMetricSnapshot.empty
        snapshot.temperatures = [
            TemperatureReading(id: "soc-1", name: "SoC 1", celsius: 49, category: .soc),
            TemperatureReading(id: "soc-2", name: "SoC 2", celsius: 51, category: .soc)
        ]

        XCTAssertEqual(snapshot.primaryTemperature, 50)
        XCTAssertEqual(snapshot.primaryTemperatureReading?.category, .soc)
    }
}
