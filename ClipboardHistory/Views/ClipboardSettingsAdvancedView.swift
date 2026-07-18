import SwiftUI

struct ClipboardSettingsAdvancedView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        Form {
            Section("Duplicate Detection") {
                Picker(
                    "Scope",
                    selection: $viewModel.settings.duplicateDetectionScope
                ) {
                    ForEach(DuplicateDetectionScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }

            Section("Clipboard Formats") {
                Toggle(
                    "Capture rich text and HTML",
                    isOn: $viewModel.settings.captureRichText
                )
                Toggle(
                    "Capture PDFs",
                    isOn: $viewModel.settings.capturePDFs
                )
                Toggle(
                    "Capture files and folders",
                    isOn: $viewModel.settings.captureFiles
                )
            }

            Section("Database") {
                LabeledContent("Migration", value: viewModel.migrationStatus)
            }

            Section {
                Text("Command-Shift-V registration can fail if another application reserves it. The native Carbon hot key does not require Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.advanced")
    }
}
