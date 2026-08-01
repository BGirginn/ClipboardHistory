import SwiftUI

struct ClipboardSettingsMessage: View {
    let message: String?
    let color: Color
    var usesLabel = false

    @ViewBuilder
    var body: some View {
        if let message {
            if usesLabel {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(color)
            } else {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
    }
}
