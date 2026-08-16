import SwiftUI

struct AppSettingsHeaderView: View {
    @Binding var selectedSection: AppSettingsSection
    @Binding var selectedSubsection: AppSettingsSubsection
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
            SettingsNavigationShelf(
                items: AppSettingsSection.allCases,
                selection: $selectedSection,
                title: \.title,
                systemImage: \.systemImage,
                buttonIdentifier: { "settings.section.\($0.rawValue)" },
                shelfIdentifier: "settings.applicationShelf"
            )
            Divider()
            SettingsNavigationShelf(
                items: selectedSection.subsections,
                selection: $selectedSubsection,
                title: \.title,
                systemImage: \.systemImage,
                buttonIdentifier: { "settings.subsection.\($0.rawValue)" },
                shelfIdentifier: "settings.subsectionShelf"
            )
        }
        .background(.bar)
    }
}
