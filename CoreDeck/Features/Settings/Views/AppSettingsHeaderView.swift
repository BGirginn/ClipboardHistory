import SwiftUI

struct AppSettingsHeaderView: View {
    @Binding var selectedSubsection: AppSettingsSubsection?
    let close: () -> Void

    var body: some View {
        HStack {
            if selectedSubsection == nil {
                Color.clear
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            } else {
                Button(
                    "All Settings",
                    systemImage: "chevron.left",
                    action: { selectedSubsection = nil }
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("All Settings")
                .accessibilityIdentifier("settings.all")
            }
            Spacer()
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier(sectionIdentifier)
            Spacer()
            OpenInWindowButton()
            Button("Close Settings", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("Close Settings")
                .accessibilityIdentifier("settings.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var title: String {
        guard let selectedSubsection else { return String(localized: "Settings") }
        return selectedSubsection.section.title + " · " + selectedSubsection.title
    }

    private var sectionIdentifier: String {
        selectedSubsection.map { "settings.section.\($0.section.rawValue)" }
            ?? "settings.title"
    }

}
