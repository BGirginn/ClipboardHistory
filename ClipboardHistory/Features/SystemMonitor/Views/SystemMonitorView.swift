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
                LazyVStack(spacing: 8) {
                    SystemMetricsOverviewGrid(controller: controller)
                    if let errorMessage = controller.errorMessage {
                        Label(errorMessage, systemImage: "thermometer.medium.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SystemMonitorDetailsView(controller: controller)
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
    }
}
