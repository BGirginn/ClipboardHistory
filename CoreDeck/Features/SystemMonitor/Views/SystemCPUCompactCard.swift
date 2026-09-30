import SwiftUI

struct SystemCPUCompactCard: View {
    let controller: SystemMetricsController

    var body: some View {
        let cpu = controller.snapshot.cpu
        CompactSystemMetricCard(
            title: String(localized: "CPU"),
            value: controller.value(for: .cpu),
            subtitle: String(localized: "System-wide, 0–100%"),
            systemImage: "cpu",
            tint: .blue,
            progress: cpu.totalPercent,
            details: [
                (String(localized: "User"), percent(cpu.userPercent)),
                (String(localized: "System"), percent(cpu.systemPercent))
            ]
        ) {
            SystemMetricSparkline(
                history: controller.history,
                value: \.cpu.totalPercent,
                color: .blue,
                maximum: 100,
                accessibilityLabel: String(localized: "CPU usage history")
            )
        }
        .accessibilityIdentifier("systemMonitor.cpu")
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
