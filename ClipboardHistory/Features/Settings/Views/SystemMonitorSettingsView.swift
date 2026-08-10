import SwiftUI

struct SystemMonitorSettingsView: View {
    @ObservedObject var viewModel: SettingsFeatureModel

    var body: some View {
        Form {
            Section("Menu Bar Metrics") {
                Toggle(
                    "Show Live Metrics in Menu Bar",
                    isOn: Binding(
                        get: { viewModel.controlCenter.configuration.metricGroup.isVisible },
                        set: { viewModel.controlCenter.setMetricGroupVisible($0) }
                    )
                )
                ForEach(MenuBarMetricID.allCases) { metric in
                    Toggle(
                        metric.title,
                        isOn: Binding(
                            get: { viewModel.controlCenter.configuration.metricGroup.metrics.contains(metric) },
                            set: { viewModel.controlCenter.setMetricVisible($0, metric: metric) }
                        )
                    )
                }
            }
            Section("Temperature") {
                LabeledContent("CPU / SoC Sensor") {
                    Text(temperature)
                        .monospacedDigit()
                }
                Text("Temperature is read directly from validated AppleSMC or Apple Silicon HID CPU/SoC die sensors. No estimated temperature is shown when a verified sensor is unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Network") {
                Picker(
                    "Interfaces",
                    selection: Binding(
                        get: { viewModel.systemMetrics.networkInterfaceScope },
                        set: { viewModel.systemMetrics.setNetworkInterfaceScope($0) }
                    )
                ) {
                    ForEach(NetworkInterfaceScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Text("The default follows the active interface. All physical interfaces excludes loopback, VPN, bridge and other virtual interfaces.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            viewModel.systemMetrics.setDemand(.detail, active: true)
            defer { viewModel.systemMetrics.setDemand(.detail, active: false) }
            try? await Task.sleep(for: .seconds(31_536_000))
        }
    }

    private var temperature: String {
        viewModel.systemMetrics.snapshot.primaryTemperature.map {
            $0.formatted(.number.precision(.fractionLength(1))) + " °C"
        } ?? String(localized: "Unavailable")
    }
}
