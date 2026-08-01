import SwiftUI

struct ClipboardSettingsAdvancedView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var newCollectionName = ""

    init(viewModel: ClipboardHistoryViewModel, newCollectionName: String = "") {
        self.viewModel = viewModel
        _newCollectionName = State(initialValue: newCollectionName)
    }

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
                Toggle(
                    "Recognize text in images on device",
                    isOn: $viewModel.settings.imageTextRecognitionEnabled
                )
            }

            Section("Ignored Pasteboard Types") {
                Toggle(
                    "Ignore Universal Clipboard",
                    isOn: $viewModel.settings.ignoreUniversalClipboard
                )
                TextField(
                    "Custom UTI identifiers",
                    text: $viewModel.settings.ignoredPasteboardTypesText,
                    axis: .vertical
                )
                .font(.body.monospaced())
                .lineLimit(2...5)
                Button(
                    "Ignore Next Copy",
                    systemImage: "eye.slash",
                    action: viewModel.ignoreNextCopy
                )
                Text("Transient, concealed, and auto-generated pasteboard types are always ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Collections") {
                HStack {
                    TextField("New collection name", text: $newCollectionName)
                        .accessibilityIdentifier("settings.newCollectionName")
                    Button("Add", systemImage: "plus", action: addCollection)
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(viewModel.collections) { collection in
                    ClipboardCollectionSettingsRow(
                        viewModel: viewModel,
                        collection: collection
                    )
                }
                Text("Collection names and item tags are encrypted at rest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paste Stack") {
                Picker("Order", selection: $viewModel.settings.pasteStackOrder) {
                    ForEach(PasteStackOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                Toggle(
                    "Remove an item after it is pasted",
                    isOn: $viewModel.settings.pasteStackRemovesUsedItems
                )
                Stepper(
                    "Reset after \(viewModel.settings.pasteStackTimeoutMinutes) minutes (0 means never)",
                    value: $viewModel.settings.pasteStackTimeoutMinutes,
                    in: 0...120
                )
                Button("Reset Paste Stack", systemImage: "xmark.circle", action: resetPasteStack)
                .disabled(viewModel.pasteStackItems.isEmpty)
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

    func addCollection() {
        viewModel.createCollection(named: newCollectionName)
        newCollectionName = ""
    }

    func resetPasteStack() {
        viewModel.resetPasteStack()
    }
}
