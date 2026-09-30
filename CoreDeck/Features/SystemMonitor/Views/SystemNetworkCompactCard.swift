import SwiftUI

struct SystemNetworkCompactCard: View {
    let controller: SystemMetricsController

    var body: some View {
        let network = controller.snapshot.network
        CompactSystemMetricCard(
            title: String(localized: "Network"),
            value: "↓ " + controller.rateValue(network.receivedBytesPerSecond),
            subtitle: "↑ " + controller.rateValue(network.sentBytesPerSecond),
            systemImage: "wifi",
            tint: .cyan,
            details: [
                (
                    String(localized: "Interface"),
                    network.interfaceName ?? String(localized: "No active interface")
                )
            ]
        ) {
            SystemDualMetricSparkline(
                history: controller.history,
                firstValue: \.network.receivedBytesPerSecond,
                secondValue: \.network.sentBytesPerSecond,
                firstColor: .cyan,
                secondColor: .blue,
                firstLabel: String(localized: "Download"),
                secondLabel: String(localized: "Upload"),
                accessibilityLabel: String(localized: "Network transfer history")
            )
        }
        .accessibilityIdentifier("systemMonitor.network")
    }
}
