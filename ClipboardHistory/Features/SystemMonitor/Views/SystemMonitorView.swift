import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var controller: SystemMetricsController
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "System Monitor"),
                subtitle: String(localized: "Live system performance"),
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) {
                Button("Refresh", systemImage: "arrow.clockwise", action: controller.refresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Refresh")
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: AppDesign.sectionSpacing) {
                    SystemMetricCard(
                        title: String(localized: "CPU"),
                        value: percent(controller.snapshot.cpu.totalPercent),
                        detail: String(localized: "User \(percent(controller.snapshot.cpu.userPercent)) · System \(percent(controller.snapshot.cpu.systemPercent))"),
                        systemImage: "cpu",
                        tint: .blue
                    )
                    SystemCPUHistoryChart(history: controller.history)
                        .padding(AppDesign.cardPadding)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
                    if !controller.snapshot.cpu.perCorePercent.isEmpty {
                        metricBreakdown(
                            title: String(localized: "CPU Cores"),
                            rows: controller.snapshot.cpu.perCorePercent.enumerated().map {
                                (String(localized: "Core \($0.offset + 1)"), percent($0.element))
                            }
                        )
                    }
                    SystemMetricCard(
                        title: String(localized: "Memory"),
                        value: percent(controller.snapshot.memory.usedPercent),
                        detail: memoryDetail,
                        systemImage: "memorychip",
                        tint: memoryTint
                    )
                    metricBreakdown(title: String(localized: "Memory Breakdown"), rows: memoryRows)
                    SystemMetricCard(
                        title: String(localized: "CPU / SoC Temperature"),
                        value: temperatureValue,
                        detail: thermalDetail,
                        systemImage: "thermometer.medium",
                        tint: .orange
                    )
                    if !controller.snapshot.temperatures.isEmpty {
                        TemperatureSensorList(
                            readings: controller.snapshot.temperatures,
                            statistics: controller.temperatureStatistics
                        )
                    }
                    SystemMetricCard(
                        title: String(localized: "Network"),
                        value: "↓ \(rate(controller.snapshot.network.receivedBytesPerSecond))  ↑ \(rate(controller.snapshot.network.sentBytesPerSecond))",
                        detail: controller.snapshot.network.interfaceName ?? String(localized: "No active interface"),
                        systemImage: "wifi",
                        tint: .cyan
                    )
                    SystemMetricCard(
                        title: String(localized: "Disk"),
                        value: "R \(rate(controller.snapshot.disk.readBytesPerSecond))  W \(rate(controller.snapshot.disk.writtenBytesPerSecond))",
                        detail: String(localized: "Combined physical storage activity"),
                        systemImage: "internaldrive",
                        tint: .purple
                    )
                    if !controller.snapshot.disk.devices.isEmpty {
                        metricBreakdown(
                            title: String(localized: "Physical Storage Devices"),
                            rows: controller.snapshot.disk.devices.map { device in
                                let location = device.isExternal
                                    ? String(localized: "External")
                                    : String(localized: "Internal")
                                return (
                                    "\(device.name) · \(location)",
                                    "R \(rate(device.readBytesPerSecond))  W \(rate(device.writtenBytesPerSecond))"
                                )
                            }
                        )
                    }
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
        .task {
            controller.setDemand(.detail, active: true)
            defer { controller.setDemand(.detail, active: false) }
            try? await Task.sleep(for: .seconds(31_536_000))
        }
    }

    private var memoryDetail: String {
        let used = byteCount(controller.snapshot.memory.usedBytes)
        let total = byteCount(controller.snapshot.memory.totalBytes)
        return String(localized: "\(used) of \(total) · Pressure: \(controller.snapshot.memory.pressure.title)")
    }

    private var memoryRows: [(String, String)] {
        let memory = controller.snapshot.memory
        return [
            (String(localized: "Active"), byteCount(memory.activeBytes)),
            (String(localized: "Inactive"), byteCount(memory.inactiveBytes)),
            (String(localized: "Wired"), byteCount(memory.wiredBytes)),
            (String(localized: "Compressed"), byteCount(memory.compressedBytes)),
            (String(localized: "Cached"), byteCount(memory.cachedBytes)),
            (String(localized: "Free"), byteCount(memory.freeBytes))
        ]
    }

    private func metricBreakdown(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                LabeledContent(row.0) {
                    Text(row.1).monospacedDigit()
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }

    private var memoryTint: Color {
        switch controller.snapshot.memory.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var temperatureValue: String {
        controller.snapshot.primaryTemperature.map {
            $0.formatted(.number.precision(.fractionLength(1))) + " °C"
        } ?? String(localized: "Unavailable")
    }

    private var thermalDetail: String {
        switch controller.snapshot.thermalState {
        case .nominal: String(localized: "Thermal state: Nominal")
        case .fair: String(localized: "Thermal state: Fair")
        case .serious: String(localized: "Thermal state: Serious")
        case .critical: String(localized: "Thermal state: Critical")
        @unknown default: String(localized: "Thermal state: Unknown")
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func byteCount(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    private func rate(_ value: Double) -> String {
        Int64(max(0, value)).formatted(.byteCount(style: .file)) + "/s"
    }
}
