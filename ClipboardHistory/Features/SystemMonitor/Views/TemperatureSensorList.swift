import SwiftUI

struct TemperatureSensorList: View {
    let readings: [TemperatureReading]
    let statistics: (String) -> (minimum: Double, average: Double, maximum: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU Sensors")
                .font(.headline)
            ForEach(readings) { reading in
                VStack(alignment: .leading, spacing: 3) {
                    LabeledContent(reading.name) {
                        Text(reading.celsius, format: .number.precision(.fractionLength(1)))
                        Text("°C")
                    }
                    if let values = statistics(reading.id) {
                        Text("Min \(temperature(values.minimum)) · Avg \(temperature(values.average)) · Max \(temperature(values.maximum))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }

    private func temperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }
}
