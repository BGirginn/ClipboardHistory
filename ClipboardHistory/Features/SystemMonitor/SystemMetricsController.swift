import Combine
import AppKit
import Foundation

@MainActor
final class SystemMetricsController: ObservableObject {
    @Published private(set) var snapshot: SystemMetricSnapshot = .empty
    private(set) var history: [SystemMetricSnapshot] = []
    private(set) var errorMessage: String?
    @Published private(set) var networkInterfaceScope: NetworkInterfaceScope

    private let provider: any SystemMetricsProviding
    private var demands: [SamplingDemandSource: SystemMetricsDemand] = [:]
    private var samplingTask: Task<Void, Never>?
    private var activeSamplingInterval: Duration?
    private var inFlightSampleTask: Task<SystemMetricSnapshot, Never>?
    private var inFlightSampleID = 0
    private let maximumHistoryCount: Int
    private let defaults: UserDefaults
    private let networkScopeKey = "systemMonitor.networkInterfaceScope.v1"
    private var workspaceCancellables: Set<AnyCancellable> = []

    init(
        provider: any SystemMetricsProviding = SystemMetricsProvider(),
        maximumHistoryCount: Int = 900,
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.maximumHistoryCount = max(maximumHistoryCount, 1)
        self.defaults = defaults
        networkInterfaceScope = defaults.string(forKey: networkScopeKey)
            .flatMap(NetworkInterfaceScope.init(rawValue:)) ?? .primaryWiFi
        Task { await provider.setNetworkInterfaceScope(networkInterfaceScope) }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.resetBaselinesAfterLifecycleChange()
                    }
                }
                .store(in: &workspaceCancellables)
        }
    }

    func setDemand(_ demand: SystemMetricsDemand?, for source: SamplingDemandSource) {
        let previousDemand = demands[source]
        if let demand {
            demands[source] = demand
        } else {
            demands.removeValue(forKey: source)
        }
        guard previousDemand != demand else { return }
        restartSamplingIfNeeded()
    }

    func setDemand(_ demand: SystemMetricsDemand, active: Bool) {
        setDemand(active ? demand : nil, for: SamplingDemandSource(id: "legacy-\(demand)"))
    }

    func refresh() {
        Task { [weak self] in await self?.sampleOnce() }
    }

    func refreshNow() async {
        await sampleOnce()
    }

    var hasActiveSampling: Bool { samplingTask != nil }
    var demandCount: Int { demands.count }

    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) {
        guard networkInterfaceScope != scope else { return }
        networkInterfaceScope = scope
        defaults.set(scope.rawValue, forKey: networkScopeKey)
        cancelInFlightSample()
        Task { [weak self] in
            guard let self else { return }
            await provider.setNetworkInterfaceScope(scope)
            guard networkInterfaceScope == scope else { return }
            await sampleOnce()
        }
    }

    func temperatureStatistics(for sensorID: String) -> (minimum: Double, average: Double, maximum: Double)? {
        temperatureStatisticsBySensorID()[sensorID]
    }

    func temperatureStatisticsBySensorID() -> [
        String: (minimum: Double, average: Double, maximum: Double)
    ] {
        var accumulators: [String: (minimum: Double, maximum: Double, total: Double, count: Int)] = [:]
        for sample in history {
            for reading in sample.temperatures {
                if var values = accumulators[reading.id] {
                    values.minimum = min(values.minimum, reading.celsius)
                    values.maximum = max(values.maximum, reading.celsius)
                    values.total += reading.celsius
                    values.count += 1
                    accumulators[reading.id] = values
                } else {
                    accumulators[reading.id] = (
                        reading.celsius,
                        reading.celsius,
                        reading.celsius,
                        1
                    )
                }
            }
        }
        return accumulators.mapValues {
            (
                minimum: $0.minimum,
                average: $0.total / Double($0.count),
                maximum: $0.maximum
            )
        }
    }

    func stop() {
        demands.removeAll()
        samplingTask?.cancel()
        samplingTask = nil
        activeSamplingInterval = nil
        cancelInFlightSample()
    }

    func value(
        for metric: MenuBarMetricID,
        snapshot presentedSnapshot: SystemMetricSnapshot? = nil,
        formats: MetricFormatPreferences = .defaults
    ) -> String {
        let snapshot = presentedSnapshot ?? snapshot
        switch metric {
        case .cpu:
            return snapshot.cpu.totalPercent.formatted(.number.precision(.fractionLength(0))) + "%"
        case .memory:
            if formats.memory == .usedAndTotal {
                return "\(compactBytes(snapshot.memory.usedBytes))/\(compactBytes(snapshot.memory.totalBytes))"
            }
            return snapshot.memory.usedPercent.formatted(.number.precision(.fractionLength(0))) + "%"
        case .temperature:
            return snapshot.primaryTemperature.map {
                let value = formats.temperature == .fahrenheit ? ($0 * 9 / 5 + 32) : $0
                let unit = formats.temperature == .fahrenheit ? "°F" : "°C"
                return value.formatted(.number.precision(.fractionLength(1))) + unit
            } ?? "—"
        case .networkDownload:
            return rateValue(snapshot.network.receivedBytesPerSecond, unit: formats.rate)
        case .networkUpload:
            return rateValue(snapshot.network.sentBytesPerSecond, unit: formats.rate)
        case .diskRead:
            return rateValue(snapshot.disk.readBytesPerSecond, unit: formats.rate)
        case .diskWrite:
            return rateValue(snapshot.disk.writtenBytesPerSecond, unit: formats.rate)
        }
    }

    func rateValue(_ value: Double, unit: RateMetricUnit = .automatic) -> String {
        let clamped = max(0, value)
        switch unit {
        case .automatic:
            if clamped < 1_000 {
                return clamped.formatted(.number.precision(.fractionLength(0))) + " B/s"
            }
            if clamped < 1_000_000 {
                return formattedRate(clamped / 1_000, suffix: " KB/s", maximumFractionDigits: 1)
            }
            if clamped < 1_000_000_000 {
                return formattedRate(clamped / 1_000_000, suffix: " MB/s", maximumFractionDigits: 1)
            }
            if clamped < 1_000_000_000_000 {
                return formattedRate(clamped / 1_000_000_000, suffix: " GB/s", maximumFractionDigits: 2)
            }
            return formattedRate(clamped / 1_000_000_000_000, suffix: " TB/s", maximumFractionDigits: 2)
        case .kilobytes:
            return formattedRate(clamped / 1_000, suffix: " KB/s", maximumFractionDigits: 1)
        case .megabytes:
            return formattedRate(clamped / 1_000_000, suffix: " MB/s", maximumFractionDigits: 1)
        case .gigabytes:
            return formattedRate(clamped / 1_000_000_000, suffix: " GB/s", maximumFractionDigits: 2)
        }
    }

    private func restartSamplingIfNeeded() {
        let desiredInterval = demands.isEmpty ? nil : samplingInterval
        guard desiredInterval != activeSamplingInterval else { return }
        samplingTask?.cancel()
        samplingTask = nil
        activeSamplingInterval = desiredInterval
        guard let desiredInterval else {
            cancelInFlightSample()
            return
        }
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await sampleOnce()
                do {
                    try await Task.sleep(for: desiredInterval)
                } catch {
                    return
                }
            }
        }
    }

    private var samplingInterval: Duration {
        if demands.values.contains(.detail) { return SystemMetricsDemand.detail.interval }
        if demands.values.contains(.menuBar) { return SystemMetricsDemand.menuBar.interval }
        return SystemMetricsDemand.controlCenter.interval
    }

    private func sampleOnce() async {
        let sampleTask: Task<SystemMetricSnapshot, Never>
        let sampleID: Int
        if let inFlightSampleTask {
            sampleTask = inFlightSampleTask
            sampleID = inFlightSampleID
        } else {
            inFlightSampleID += 1
            sampleID = inFlightSampleID
            sampleTask = Task { [provider] in
                await provider.sample(at: .now)
            }
            inFlightSampleTask = sampleTask
        }
        let sample = await sampleTask.value
        guard sampleID == inFlightSampleID,
              inFlightSampleTask != nil else { return }
        inFlightSampleTask = nil
        guard sample.timestamp >= snapshot.timestamp else { return }
        history.append(sample)
        history.removeAll { $0.timestamp < sample.timestamp.addingTimeInterval(-15 * 60) }
        if history.count > maximumHistoryCount {
            history.removeFirst(history.count - maximumHistoryCount)
        }
        let updatedErrorMessage = sample.temperatures.isEmpty
            ? String(localized: "Temperature data is unavailable on this Mac.")
            : nil
        errorMessage = updatedErrorMessage
        snapshot = sample
    }

    private func cancelInFlightSample() {
        inFlightSampleID += 1
        inFlightSampleTask?.cancel()
        inFlightSampleTask = nil
    }

    private func resetBaselinesAfterLifecycleChange() async {
        cancelInFlightSample()
        await provider.resetBaselines()
    }

    private func formattedRate(
        _ value: Double,
        suffix: String,
        maximumFractionDigits: Int
    ) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...maximumFractionDigits))
        ) + suffix
    }

    private func compactBytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }
}
