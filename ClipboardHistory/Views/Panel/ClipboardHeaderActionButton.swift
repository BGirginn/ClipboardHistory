import SwiftUI

struct ClipboardHeaderActionButton: View {
    let title: String
    let systemImage: String
    let helpText: String
    let accessibilityIdentifier: String
    let accessibilityValue: String
    var isActive = false
    var isDisabled = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .background(
                isActive ? tint.opacity(0.16) : Color.clear,
                in: .rect(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? tint.opacity(0.55) : .clear, lineWidth: 1)
            }
            .foregroundStyle(isActive ? tint : .primary)
            .disabled(isDisabled)
            .help(helpText)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
