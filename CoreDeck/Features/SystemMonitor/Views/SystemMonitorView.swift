import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var controller: SystemMetricsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetails = false
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
                    SystemMetricsSummaryView(controller: controller)
                    if let errorMessage = controller.errorMessage {
                        Label(errorMessage, systemImage: "thermometer.medium.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        if reduceMotion {
                            showsDetails.toggle()
                        } else {
                            withAnimation {
                                showsDetails.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showsDetails ? 90 : 0))
                            Text("Charts and Sensors")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("systemMonitor.details")
                    .accessibilityValue(
                        showsDetails ? String(localized: "Expanded") : String(localized: "Collapsed")
                    )
                    if showsDetails {
                        SystemMetricsOverviewGrid(controller: controller)
                        SystemMonitorDetailsView(controller: controller)
                    }
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
    }
}
