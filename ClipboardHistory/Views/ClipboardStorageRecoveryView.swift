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
            #if COMMUNITY
            GroupBox("Migrate from Apple Development Build") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select the password-protected full archive exported by the Apple Development build. The current database is retained as a rollback backup until the import is verified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Archive password", text: $archivePassword)
                    Button("Import Migration Archive…", systemImage: "lock.rotation") {
                        viewModel.importCommunityMigrationArchive(password: archivePassword)
                    }
                    .disabled(archivePassword.isEmpty)
                }
                .padding(6)
            }
            #endif
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
