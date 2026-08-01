import SwiftUI

struct ClipboardLockedHistoryView: View {
    let unlock: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Clipboard History Locked", systemImage: "lock.fill")
        } description: {
            Text("Authenticate with Touch ID or your Mac login password to view, copy, or paste saved items.")
        } actions: {
            Button("Authenticate and Unlock", systemImage: "touchid", action: unlock)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Uses system authentication. Clipboard History does not store a separate password.")
                .accessibilityIdentifier("locked.unlock")
        }
        .accessibilityIdentifier("clipboard.locked")
    }
}
