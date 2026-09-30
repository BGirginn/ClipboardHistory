import SwiftUI

struct SystemMemoryCompactCard: View {
    let controller: SystemMetricsController

    var body: some View {
        let memory = controller.snapshot.memory
        CompactSystemMetricCard(
            title: String(localized: "Memory"),
            value: controller.value(for: .memory),
            subtitle: "\(bytes(memory.usedBytes)) / \(bytes(memory.totalBytes))",
            systemImage: "memorychip",
            tint: tint,
            progress: memory.usedPercent,
            details: [
                (String(localized: "Memory Pressure"), memory.pressure.title),
                (String(localized: "Free"), bytes(memory.freeBytes))
            ]
        ) {
            SystemMetricSparkline(
                history: controller.history,
                value: \.memory.usedPercent,
                color: tint,
                maximum: 100,
                accessibilityLabel: String(localized: "Memory usage history")
            )
        }
        .accessibilityIdentifier("systemMonitor.memory")
    }

    private var tint: Color {
        switch controller.snapshot.memory.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }
}
