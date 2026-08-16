import SwiftUI

struct SettingsShelfButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .onHover { isHovering = $0 }
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected { return .accentColor }
        if isHovering { return Color(nsColor: .selectedControlColor).opacity(0.14) }
        return .clear
    }

    private var borderColor: Color {
        isSelected ? .accentColor : Color(nsColor: .separatorColor)
    }
}
