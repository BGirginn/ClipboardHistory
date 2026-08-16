import SwiftUI

struct ClipboardSettingsGeneralView: View {
    @ObservedObject var viewModel: SettingsFeatureModel

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle(
                    "Enable global shortcut",
                    isOn: $viewModel.settings.globalShortcutEnabled
                )
                .accessibilityIdentifier("settings.globalShortcut")

                ClipboardSettingsMessage(
                    message: viewModel.globalShortcutError,
                    color: .orange,
                    usesLabel: true
                )

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
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.general")
    }

}
