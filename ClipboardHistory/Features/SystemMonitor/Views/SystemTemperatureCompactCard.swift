import SwiftUI

struct SystemTemperatureCompactCard: View {
    let controller: SystemMetricsController

    var body: some View {
        let primary = controller.snapshot.primaryTemperatureReading
        let temperature = primary?.celsius
        CompactSystemMetricCard(
            title: primary.map {
                String(localized: "\($0.localizedSourceName) Temperature")
            } ?? String(localized: "Temperature"),
            value: temperature.map(value) ?? "—",
            subtitle: thermalState,
            systemImage: "thermometer.medium",
            tint: .orange,
            progress: temperature,
            details: [
                (
                    String(localized: "Sensor Source"),
                    primary?.localizedSourceName ?? "—"
                )
            ]
        ) {
            SystemTemperatureSparkline(history: controller.history)
        }
        .accessibilityIdentifier("systemMonitor.temperature")
    }

    private var thermalState: String {
        switch controller.snapshot.thermalState {
        case .nominal: String(localized: "Thermal state: Nominal")
        case .fair: String(localized: "Thermal state: Fair")
        case .serious: String(localized: "Thermal state: Serious")
        case .critical: String(localized: "Thermal state: Critical")
        @unknown default: String(localized: "Thermal state: Unknown")
        }
    }

    private func value(_ temperature: Double) -> String {
        temperature.formatted(.number.precision(.fractionLength(1))) + "°C"
    }
}
