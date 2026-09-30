import SwiftUI

struct SettingsNavigationList: View {
    @Binding var selection: AppSettingsSubsection?

    var body: some View {
        List(selection: $selection) {
            ForEach(AppSettingsSection.allCases) { section in
                Section {
                    ForEach(section.subsections) { subsection in
                        Label(subsection.title, systemImage: subsection.systemImage)
                            .tag(subsection)
                            .accessibilityIdentifier(
                                "settings.subsection.\(subsection.rawValue)"
                            )
                    }
                } header: {
                    Text(section.title)
                        .accessibilityIdentifier("settings.group.\(section.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .accessibilityIdentifier("settings.navigationList")
    }
}
