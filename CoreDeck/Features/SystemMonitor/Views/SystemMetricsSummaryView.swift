import SwiftUI

struct SystemMetricsSummaryView: View {
    @ObservedObject var controller: SystemMetricsController

    var body: some View {
        VStack(spacing: 0) {
            ForEach([MenuBarMetricID.cpu, .memory, .temperature, .networkDownload, .networkUpload, .diskRead, .diskWrite]) { metric in
                HStack {
                    Text(metric.title).foregroundStyle(.secondary)
                    Spacer()
                    Text(controller.hasSample ? controller.value(for: metric) : "—")
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                .padding(.vertical, 9)
                .accessibilityIdentifier("systemMonitor.\(metric.rawValue)")
                if metric != .diskWrite { Divider() }
            }
        }
        .padding(.horizontal, AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: AppDesign.cardCornerRadius))
    }
}
