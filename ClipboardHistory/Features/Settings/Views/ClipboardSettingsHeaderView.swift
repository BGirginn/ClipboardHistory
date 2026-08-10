import SwiftUI

struct ClipboardSettingsHeaderView: View {
    @Binding var selectedSection: ClipboardSettingsSection
    let close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .help("Return to previous screen")
                    .accessibilityIdentifier("settings.back")

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                Color.clear
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }

            Picker("Settings Section", selection: $selectedSection) {
                ForEach(ClipboardSettingsSection.allCases) { section in
                    Image(systemName: section.systemImage)
                        .accessibilityLabel(section.title)
                        .tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityValue(selectedSection.title)
            .accessibilityIdentifier("settings.sectionPicker")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
