import Combine
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

    func value(for metric: MenuBarMetricID) -> String {
        switch metric {
        case .cpu:
            snapshot.cpu.totalPercent.formatted(.number.precision(.fractionLength(0))) + "%"
        case .memory:
            snapshot.memory.usedPercent.formatted(.number.precision(.fractionLength(0))) + "%"
        case .temperature:
            snapshot.primaryTemperature.map {
                $0.formatted(.number.precision(.fractionLength(0))) + "°C"
            } ?? "—"
        case .networkDownload:
            rateString(snapshot.network.receivedBytesPerSecond)
        case .networkUpload:
            rateString(snapshot.network.sentBytesPerSecond)
        case .diskRead:
            rateString(snapshot.disk.readBytesPerSecond)
        case .diskWrite:
            rateString(snapshot.disk.writtenBytesPerSecond)
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

    private func rateString(_ value: Double) -> String {
        Int64(max(0, value)).formatted(.byteCount(style: .file)) + "/s"
    }
}
