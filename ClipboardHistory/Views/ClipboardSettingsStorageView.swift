import SwiftUI

struct ClipboardSettingsStorageView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var archivePassword = ""
    @State private var includeArchiveAssets = true
    @State private var includeArchiveFileReferences = true
    @State private var confirmUnencryptedExport = false

    init(
        viewModel: ClipboardHistoryViewModel,
        archivePassword: String = "",
        includeArchiveAssets: Bool = true,
        includeArchiveFileReferences: Bool = true,
        confirmUnencryptedExport: Bool = false
    ) {
        self.viewModel = viewModel
        _archivePassword = State(initialValue: archivePassword)
        _includeArchiveAssets = State(initialValue: includeArchiveAssets)
        _includeArchiveFileReferences = State(initialValue: includeArchiveFileReferences)
        _confirmUnencryptedExport = State(initialValue: confirmUnencryptedExport)
    }

    var body: some View {
        Form {
            Section("Retention") {
                LabeledContent("History age") {
                    Stepper(
                        value: $viewModel.settings.retentionDays,
                        in: 1...3_650
                    ) {
                        daysLabel(viewModel.settings.retentionDays)
                    }
                }

                LabeledContent("Image age") {
                    Stepper(
                        value: $viewModel.settings.imageRetentionDays,
                        in: 1...3_650
                    ) {
                        daysLabel(viewModel.settings.imageRetentionDays)
                    }
                }

                LabeledContent("Maximum storage") {
                    Stepper(
                        value: $viewModel.settings.maximumStorageMegabytes,
                        in: 50...20_480,
                        step: 50
                    ) {
                        Text(
                            Int64(viewModel.settings.maximumStorageMegabytes) * 1_000_000,
                            format: .byteCount(style: .file)
                        )
                        .monospacedDigit()
                    }
                }

                LabeledContent("Thumbnail cache") {
                    Stepper(
                        value: $viewModel.settings.thumbnailCacheMegabytes,
                        in: 8...512,
                        step: 8
                    ) {
                        Text(
                            Int64(viewModel.settings.thumbnailCacheMegabytes) * 1_000_000,
                            format: .byteCount(style: .file)
                        )
                        .monospacedDigit()
                    }
                }
            }

            Section("Usage") {
                LabeledContent(
                    "Database",
                    value: viewModel.storageMetrics.databaseBytes.formatted(
                        .byteCount(style: .file)
                    )
                )
                LabeledContent(
                    "Images",
                    value: viewModel.storageMetrics.imageBytes.formatted(
                        .byteCount(style: .file)
                    )
                )
                LabeledContent(
                    "Thumbnails",
                    value: viewModel.storageMetrics.thumbnailBytes.formatted(
                        .byteCount(style: .file)
                    )
                )
                LabeledContent(
                    "Documents",
                    value: viewModel.storageMetrics.payloadBytes.formatted(
                        .byteCount(style: .file)
                    )
                )

                HStack {
                    Button("Run Cleanup", systemImage: "sparkles", action: runCleanup)
                    Button(
                        "Clear History",
                        systemImage: "trash",
                        role: .destructive,
                        action: viewModel.clearHistory
                    )
                }
                .buttonStyle(.bordered)
            }

            Section("Local Archive") {
                Toggle(
                    "Include images and documents",
                    isOn: $includeArchiveAssets
                )
                Toggle(
                    "Include file references",
                    isOn: $includeArchiveFileReferences
                )
                SecureField("Archive password", text: $archivePassword)

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Button("Metadata Export", action: exportMetadata)
                        Button("Encrypted Export", action: exportEncrypted)
                            .disabled(archivePassword.isEmpty)
                    }
                    GridRow {
                        Button("Unencrypted Export", action: requestUnencryptedExport)
                        Button("Merge Import", action: importArchive)
                    }
                }
                .buttonStyle(.bordered)

                ClipboardSettingsMessage(
                    message: viewModel.archiveStatusMessage,
                    color: .secondary
                )
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Export clipboard content without encryption?",
            isPresented: $confirmUnencryptedExport
        ) {
            Button("Export Unencrypted", action: exportUnencrypted)
            Button("Cancel", role: .cancel, action: cancelDialog)
        } message: {
            Text("The export can contain clipboard text and document data in readable form.")
        }
        .accessibilityIdentifier("settings.storage")
    }

    private func daysLabel(_ value: Int) -> some View {
        Text("\(value) \(value == 1 ? "day" : "days")")
            .monospacedDigit()
    }

    func runCleanup() {
        Task {
            await viewModel.runRetentionCleanup()
            await viewModel.refreshStorageInformation()
        }
    }

    func exportMetadata() {
        viewModel.exportArchive(
            mode: .metadataOnly,
            includeImagesAndDocuments: false,
            includeFileReferences: includeArchiveFileReferences
        )
    }

    func exportEncrypted() {
        viewModel.exportArchive(
            mode: .encrypted,
            includeImagesAndDocuments: includeArchiveAssets,
            includeFileReferences: includeArchiveFileReferences,
            password: archivePassword
        )
    }

    func requestUnencryptedExport() {
        confirmUnencryptedExport = true
    }

    func exportUnencrypted() {
        viewModel.exportArchive(
            mode: .fullUnencrypted,
            includeImagesAndDocuments: includeArchiveAssets,
            includeFileReferences: includeArchiveFileReferences
        )
    }

    func importArchive() {
        viewModel.importArchive(
            password: archivePassword.isEmpty ? nil : archivePassword
        )
    }

    func cancelDialog() {}
}
