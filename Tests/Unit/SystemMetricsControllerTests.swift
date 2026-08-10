import XCTest

@testable import ClipboardHistory

private actor SystemMetricsProviderStub: SystemMetricsProviding {
    private var index = 0

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
}

@MainActor
final class SystemMetricsControllerTests: XCTestCase {
    func testRefreshPublishesCompleteNumericSnapshotAndFormatsMenuBarValues() async {
        let controller = SystemMetricsController(provider: SystemMetricsProviderStub())

        await controller.refreshNow()

        XCTAssertEqual(controller.snapshot.cpu.totalPercent, 1)
        XCTAssertEqual(controller.snapshot.memory.usedPercent, 50)
        XCTAssertEqual(controller.snapshot.primaryTemperature, 54)
        XCTAssertEqual(controller.value(for: .cpu), "1%")
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
}
