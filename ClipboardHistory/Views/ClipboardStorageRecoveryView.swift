import SwiftUI

struct ClipboardStorageRecoveryView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var archivePassword = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Encrypted Storage Unavailable")
                .font(.title2.bold())
            Text(viewModel.errorMessage ?? "Clipboard recording is stopped so no content can be stored without encryption.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            GroupBox("Recover from Encrypted Archive") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select a password-protected full archive. The unavailable database is retained as a rollback backup until the import is verified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Archive password", text: $archivePassword)
                    Button("Import Recovery Archive…", systemImage: "lock.rotation") {
                        viewModel.importStorageRecoveryArchive(password: archivePassword)
                    }
                    .disabled(archivePassword.isEmpty)
                }
                .padding(6)
            }
            if let status = viewModel.archiveStatusMessage {
                Text(status)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("storage.recovery")
    }
}
