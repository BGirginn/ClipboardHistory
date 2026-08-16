import SwiftUI

struct AppPreferencesView: View {
    @ObservedObject var viewModel: SettingsFeatureModel
    @ObservedObject private var launchAtLoginService: LaunchAtLoginService
    let selectedSubsection: AppSettingsSubsection

    init(
        viewModel: SettingsFeatureModel,
        selectedSubsection: AppSettingsSubsection = .appPresentation
    ) {
        self.viewModel = viewModel
        self.selectedSubsection = selectedSubsection
        _launchAtLoginService = ObservedObject(
            wrappedValue: viewModel.launchAtLoginService
        )
    }

    var body: some View {
        Form {
            if selectedSubsection == .appPresentation {
                Section("Presentation") {
                    Picker("Appearance", selection: $viewModel.settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")

                    Picker("Panel style", selection: $viewModel.settings.panelPresentationMode) {
                        ForEach(PanelPresentationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Screen edge", selection: $viewModel.settings.panelScreenEdge) {
                        ForEach(PanelScreenEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .disabled(viewModel.settings.panelPresentationMode == .popover)
                }
            }

            if selectedSubsection == .appStartup {
                Section("Startup") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .accessibilityIdentifier("settings.launchAtLogin")
                    ClipboardSettingsMessage(
                        message: launchAtLoginService.errorMessage,
                        color: .red,
                        usesLabel: true
                    )
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.general")
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginService.isEnabled },
            set: viewModel.setLaunchAtLogin
        )
    }
}
