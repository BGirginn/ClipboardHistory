import Foundation

protocol SystemMetricsProviding: Sendable {
    func sample(at date: Date) async -> SystemMetricSnapshot
    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) async
    func resetBaselines() async
}

extension SystemMetricsProviding {
    func setNetworkInterfaceScope(_ scope: NetworkInterfaceScope) async {}
    func resetBaselines() async {}
}
