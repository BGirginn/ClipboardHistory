import SwiftUI

struct SettingsNavigationList: View {
    @Binding var selection: AppSettingsSubsection?

    var body: some View {
        List {
            ForEach(AppSettingsSection.allCases) { section in
                Section {
                    ForEach(section.subsections.filter { $0 != .appStartup }) { subsection in
                        Button {
                            selection = subsection
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: subsection.systemImage)
                                    .frame(width: 20)
                                    .foregroundStyle(.tint)
                                Text(subsection.title)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
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
        .accessibilityIdentifier("settings.navigationList")
    }
}
