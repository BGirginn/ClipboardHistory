import Charts
import SwiftUI

struct SystemDualMetricSparkline: View {
    let history: [SystemMetricSnapshot]
    let firstValue: KeyPath<SystemMetricSnapshot, Double>
    let secondValue: KeyPath<SystemMetricSnapshot, Double>
    let firstColor: Color
    let secondColor: Color
    let firstLabel: String
    let secondLabel: String
    let accessibilityLabel: String

    var body: some View {
        Chart {
            ForEach(history.suffix(90), id: \.timestamp) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(firstLabel, sample[keyPath: firstValue]),
                    series: .value("Series", firstLabel)
                )
                .foregroundStyle(firstColor)
                .lineStyle(.init(lineWidth: 1.5))
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(secondLabel, sample[keyPath: secondValue]),
                    series: .value("Series", secondLabel)
                )
                .foregroundStyle(secondColor)
                .lineStyle(.init(lineWidth: 1.5))
            }
        }
        .chartXScale(range: .plotDimension(padding: 0))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
        .accessibilityLabel(accessibilityLabel)
    }
}
