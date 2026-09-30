import Charts
import SwiftUI

struct SystemDualMetricHistoryChart: View {
    let title: String
    let firstLabel: String
    let secondLabel: String
    let firstColor: Color
    let secondColor: Color
    let history: [SystemMetricSnapshot]
    let firstValue: (SystemMetricSnapshot) -> Double
    let secondValue: (SystemMetricSnapshot) -> Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart {
                ForEach(history.suffix(900), id: \.timestamp) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value(firstLabel, firstValue(sample)),
                        series: .value("Series", firstLabel)
                    ).foregroundStyle(firstColor)
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value(secondLabel, secondValue(sample)),
                        series: .value("Series", secondLabel)
                    ).foregroundStyle(secondColor)
                }
            }
            .chartXAxis(.hidden)
            .frame(minHeight: 100)
            .accessibilityLabel(title)
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }
}
