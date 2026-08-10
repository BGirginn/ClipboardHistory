import Charts
import SwiftUI

struct SystemCPUHistoryChart: View {
    let history: [SystemMetricSnapshot]

    var body: some View {
        Chart(history.suffix(120), id: \.timestamp) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("CPU", sample.cpu.totalPercent)
            )
            .foregroundStyle(.blue)
            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("CPU", sample.cpu.totalPercent)
            )
            .foregroundStyle(.blue.opacity(0.12))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .frame(minHeight: 110)
        .accessibilityLabel("CPU usage history")
    }
}
