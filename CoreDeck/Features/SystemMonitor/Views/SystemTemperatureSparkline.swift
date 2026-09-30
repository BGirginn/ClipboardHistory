import Charts
import SwiftUI

struct SystemTemperatureSparkline: View {
    let history: [SystemMetricSnapshot]

    var body: some View {
        Chart(history.suffix(90), id: \.timestamp) { sample in
            if let temperature = sample.primaryTemperature {
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Temperature", temperature)
                )
                .foregroundStyle(.orange)
                .lineStyle(.init(lineWidth: 1.5))
            }
        }
        .chartXScale(range: .plotDimension(padding: 0))
        .chartYScale(domain: 20...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
        .accessibilityLabel("Temperature history")
    }
}
