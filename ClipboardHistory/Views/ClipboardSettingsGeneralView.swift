import SwiftUI

struct ClipboardSettingsGeneralView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject private var launchAtLoginService: LaunchAtLoginService

    init(viewModel: ClipboardHistoryViewModel) {
        self.viewModel = viewModel
        _launchAtLoginService = ObservedObject(
            wrappedValue: viewModel.launchAtLoginService
        )
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle(
                    "Enable global shortcut",
                    isOn: $viewModel.settings.globalShortcutEnabled
                )
                .accessibilityIdentifier("settings.globalShortcut")

                if let shortcutError = viewModel.globalShortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle(
                    "Close panel after copying",
                    isOn: $viewModel.settings.closePanelAfterCopying
                )

                LabeledContent("History limit") {
                    Stepper(
                        value: $viewModel.settings.historyLimit,
                        in: 10...5_000,
                        step: 10
                    ) {
                        Text(viewModel.settings.historyLimit, format: .number)
                            .monospacedDigit()
                    }
                }
            }

            Section("Global Shortcut") {
                Picker("Shortcut", selection: $viewModel.settings.globalShortcutPresetID) {
                    ForEach(GlobalShortcut.presets) { shortcut in
                        Text(shortcut.title).tag(shortcut.id)
                    }
                }
                Picker("Action", selection: $viewModel.settings.shortcutActivationMode) {
                    ForEach(ShortcutActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("Hold mode requests Accessibility permission only when release triggers Paste to Active App.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Presentation") {
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
                Picker("Default filter", selection: $viewModel.settings.selectedFilter) {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }

                Picker("Default sort", selection: $viewModel.settings.selectedSortMode) {
                    ForEach(ClipboardSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .accessibilityIdentifier("settings.launchAtLogin")

                if let error = launchAtLoginService.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.general")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginService.isEnabled },
            set: { enabled in
                viewModel.setLaunchAtLogin(enabled)
            }
        )
    }
}
