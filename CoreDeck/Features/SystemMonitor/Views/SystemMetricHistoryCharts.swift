import Charts
import SwiftUI

struct SystemMetricHistoryChart: View {
    let title: String
    let color: Color
    let history: [SystemMetricSnapshot]
    let value: (SystemMetricSnapshot) -> Double
    let fixedMaximum: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(history.suffix(900), id: \.timestamp) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(title, value(sample))
                ).foregroundStyle(color)
            }
            .chartYScale(domain: 0...(fixedMaximum ?? dynamicMaximum))
            .chartXAxis(.hidden)
            .frame(minHeight: 100)
            .accessibilityLabel(title)
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }

    private var dynamicMaximum: Double {
        max(history.suffix(900).map(value).max() ?? 1, 1)
    }
}
