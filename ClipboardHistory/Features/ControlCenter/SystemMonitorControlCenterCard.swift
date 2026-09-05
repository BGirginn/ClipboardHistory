import SwiftUI

struct SystemMonitorControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: SystemMetricsController
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: summary,
            systemImage: "gauge.with.dots.needle.67percent",
            accessorySystemImage: "chevron.right",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }

    private var summary: String {
        let cpu = controller.snapshot.cpu.totalPercent.formatted(
            .number.precision(.fractionLength(0))
        )
        let memory = controller.snapshot.memory.usedPercent.formatted(
            .number.precision(.fractionLength(0))
        )
        let temperature = controller.snapshot.primaryTemperature.map {
            $0.formatted(.number.precision(.fractionLength(0))) + "°C"
        } ?? "—"
        return "CPU \(cpu)% · RAM \(memory)% · \(temperature)"
    }
}
