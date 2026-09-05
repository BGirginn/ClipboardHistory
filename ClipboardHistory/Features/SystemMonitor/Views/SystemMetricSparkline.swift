import Charts
import SwiftUI

struct SystemMetricSparkline: View {
    let history: [SystemMetricSnapshot]
    let value: KeyPath<SystemMetricSnapshot, Double>
    let color: Color
    let maximum: Double
    let accessibilityLabel: String

    var body: some View {
        Chart(history.suffix(90), id: \.timestamp) { sample in
            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value(accessibilityLabel, sample[keyPath: value])
            )
            .foregroundStyle(color.opacity(0.14))
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value(accessibilityLabel, sample[keyPath: value])
            )
            .foregroundStyle(color)
            .lineStyle(.init(lineWidth: 1.5))
        }
        .chartXScale(range: .plotDimension(padding: 0))
        .chartYScale(domain: 0...maximum)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
        .accessibilityLabel(accessibilityLabel)
    }
}
