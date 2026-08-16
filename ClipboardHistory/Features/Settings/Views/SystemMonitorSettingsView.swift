import SwiftUI

struct SystemMonitorSettingsView: View {
    @ObservedObject var controller: SystemMetricsController
    let selectedSubsection: AppSettingsSubsection

    init(
        controller: SystemMetricsController,
        selectedSubsection: AppSettingsSubsection = .systemTemperature
    ) {
        self.controller = controller
        self.selectedSubsection = selectedSubsection
    }

    var body: some View {
        Form {
            if selectedSubsection == .systemTemperature {
                Section("Temperature") {
                    LabeledContent("CPU / SoC Sensor") {
                        Text(temperature)
                            .monospacedDigit()
                    }
                    Text("Temperature is read directly from validated AppleSMC or Apple Silicon HID CPU/SoC die sensors. No estimated temperature is shown when a verified sensor is unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if selectedSubsection == .systemNetwork {
                Section("Network") {
                    Picker(
                        "Interfaces",
                        selection: Binding(
                            get: { controller.networkInterfaceScope },
                            set: { controller.setNetworkInterfaceScope($0) }
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
        }
        .formStyle(.grouped)
        .task {
            controller.setDemand(.detail, active: true)
            defer { controller.setDemand(.detail, active: false) }
            try? await Task.sleep(for: .seconds(31_536_000))
        }
    }

    private var temperature: String {
        controller.snapshot.primaryTemperature.map {
            $0.formatted(.number.precision(.fractionLength(1))) + " °C"
        } ?? String(localized: "Unavailable")
    }
}
