import SwiftUI

struct SystemMonitorDetailsView: View {
    let controller: SystemMetricsController

    var body: some View {
        let rows = memoryRows
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("Memory Breakdown") {
                VStack(spacing: 5) {
                    ForEach(rows.indices, id: \.self) { index in
                        LabeledContent(rows[index].label) {
                            Text(rows[index].value).monospacedDigit()
                        }
                    }
                }
                .padding(.top, 6)
            }
            if !controller.snapshot.temperatures.isEmpty {
                Divider()
                DisclosureGroup("Temperature Sensors") {
                    TemperatureSensorList(
                        readings: controller.snapshot.temperatures,
                        statistics: controller.temperatureStatisticsBySensorID()
                    )
                    .padding(.top, 6)
                }
            }
            if !controller.snapshot.disk.devices.isEmpty {
                Divider()
                DisclosureGroup("Physical Storage Devices") {
                    VStack(spacing: 5) {
                        ForEach(controller.snapshot.disk.devices) { device in
                            LabeledContent(deviceLabel(device)) {
                                Text(
                                    "R \(controller.rateValue(device.readBytesPerSecond)) "
                                        + "W \(controller.rateValue(device.writtenBytesPerSecond))"
                                )
                                .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .font(.subheadline)
        .padding(AppDesign.compactCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }

    private var memoryRows: [(label: String, value: String)] {
        let memory = controller.snapshot.memory
        return [
            (String(localized: "Used"), bytes(memory.usedBytes)),
            (String(localized: "Application Memory"), bytes(memory.applicationBytes)),
            (String(localized: "Wired"), bytes(memory.wiredBytes)),
            (String(localized: "Compressed"), bytes(memory.compressedBytes)),
            (String(localized: "Purgeable"), bytes(memory.purgeableBytes)),
            (String(localized: "Cached"), bytes(memory.cachedBytes)),
            (String(localized: "Free"), bytes(memory.freeBytes))
        ]
    }

    private func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    private func deviceLabel(_ device: DiskDeviceRate) -> String {
        let location = device.isExternal
            ? String(localized: "External")
            : String(localized: "Internal")
        return "\(device.name) · \(location)"
    }
}
