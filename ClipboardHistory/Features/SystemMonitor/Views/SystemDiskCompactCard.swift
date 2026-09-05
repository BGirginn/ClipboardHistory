import SwiftUI

struct SystemDiskCompactCard: View {
    let controller: SystemMetricsController

    var body: some View {
        let disk = controller.snapshot.disk
        CompactSystemMetricCard(
            title: String(localized: "Disk"),
            value: "R " + controller.rateValue(disk.readBytesPerSecond),
            subtitle: "W " + controller.rateValue(disk.writtenBytesPerSecond),
            systemImage: "internaldrive",
            tint: .purple,
            details: [
                (
                    String(localized: "Physical Storage Devices"),
                    disk.devices.count.formatted()
                )
            ]
        ) {
            SystemDualMetricSparkline(
                history: controller.history,
                firstValue: \.disk.readBytesPerSecond,
                secondValue: \.disk.writtenBytesPerSecond,
                firstColor: .purple,
                secondColor: .pink,
                firstLabel: String(localized: "Read"),
                secondLabel: String(localized: "Write"),
                accessibilityLabel: String(localized: "Disk activity history")
            )
        }
        .accessibilityIdentifier("systemMonitor.disk")
    }
}
