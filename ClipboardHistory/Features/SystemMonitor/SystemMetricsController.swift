import Combine
import AppKit
import Foundation

@MainActor
final class SystemMetricsController: ObservableObject {
    @Published private(set) var snapshot: SystemMetricSnapshot = .empty
    @Published private(set) var history: [SystemMetricSnapshot] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var networkInterfaceScope: NetworkInterfaceScope

    private let provider: any SystemMetricsProviding
    private var demands: Set<SystemMetricsDemand> = []
    private var samplingTask: Task<Void, Never>?
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
                    guard let self else { return }
                    Task { await self.provider.resetBaselines() }
                }
                .store(in: &workspaceCancellables)
        }
    }

    func setDemand(_ demand: SystemMetricsDemand, active: Bool) {
        if active {
            demands.insert(demand)
        } else {
            demands.remove(demand)
        }
        restartSamplingIfNeeded()
    }

    func refresh() {
        Task { [weak self] in await self?.sampleOnce() }
    }

    func refreshNow() async {
        await sampleOnce()
    }

    var hasActiveSampling: Bool { samplingTask != nil }

    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) {
        networkInterfaceScope = scope
        defaults.set(scope.rawValue, forKey: networkScopeKey)
        Task { [weak self] in
            guard let self else { return }
            await provider.setNetworkInterfaceScope(scope)
            await sampleOnce()
        }
    }

    func temperatureStatistics(for sensorID: String) -> (minimum: Double, average: Double, maximum: Double)? {
        let values = history.compactMap { snapshot in
            snapshot.temperatures.first(where: { $0.id == sensorID })?.celsius
        }
        guard let minimum = values.min(), let maximum = values.max(), !values.isEmpty else { return nil }
        return (minimum, values.reduce(0, +) / Double(values.count), maximum)
    }

    func stop() {
        demands.removeAll()
        samplingTask?.cancel()
        samplingTask = nil
    }

    func value(
        for metric: MenuBarMetricID,
        formats: MetricFormatPreferences = .defaults
    ) -> String {
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
                return value.formatted(.number.precision(.fractionLength(0))) + unit
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
        samplingTask?.cancel()
        samplingTask = nil
        guard !demands.isEmpty else { return }
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await sampleOnce()
                do {
                    try await Task.sleep(for: samplingInterval)
                } catch {
                    return
                }
            }
        }
    }

    private var samplingInterval: Duration {
        if demands.contains(.detail) { return SystemMetricsDemand.detail.interval }
        if demands.contains(.menuBar) { return SystemMetricsDemand.menuBar.interval }
        return SystemMetricsDemand.controlCenter.interval
    }

    private func sampleOnce() async {
        let sample = await provider.sample(at: .now)
        guard !Task.isCancelled else { return }
        snapshot = sample
        history.append(sample)
        history.removeAll { $0.timestamp < sample.timestamp.addingTimeInterval(-15 * 60) }
        if history.count > maximumHistoryCount {
            history.removeFirst(history.count - maximumHistoryCount)
        }
        errorMessage = sample.temperatures.isEmpty
            ? String(localized: "CPU temperature is unavailable on this Mac.")
            : nil
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
