import SwiftUI

struct AppSettingsView: View {
    let viewModel: SettingsFeatureModel
    let initialSection: AppSettingsSection?
    let initialSubsection: AppSettingsSubsection?
    let close: () -> Void
    let selectionChanged: (AppSettingsSubsection?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSubsection: AppSettingsSubsection?

    init(
        viewModel: SettingsFeatureModel,
        initialSection: AppSettingsSection? = nil,
        initialSubsection: AppSettingsSubsection? = nil,
        close: @escaping () -> Void = {},
        selectionChanged: @escaping (AppSettingsSubsection?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.initialSection = initialSection
        self.initialSubsection = initialSubsection
        self.close = close
        self.selectionChanged = selectionChanged
        _selectedSubsection = State(
            initialValue: Self.resolveSubsection(
                initialSubsection,
                for: initialSection
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppSettingsHeaderView(
                selectedSubsection: $selectedSubsection,
                close: close
            )
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            Group {
                if let selectedSubsection {
                    AppSettingsContentView(
                        selectedSection: selectedSubsection.section,
                        selectedSubsection: selectedSubsection,
                        viewModel: viewModel
                    )
                    .id("settings.content.\(selectedSubsection.rawValue)")
                } else {
                    SettingsNavigationList(selection: $selectedSubsection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .transition(.opacity)
        }
        .animation(
            AppMotion.transition(reduceMotion: reduceMotion),
            value: selectedSubsection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: initialSection) { _, section in
            selectedSubsection = Self.resolveSubsection(
                initialSubsection,
                for: section
            )
        }
        .onChange(of: initialSubsection) { _, subsection in
            selectedSubsection = subsection
                ?? Self.resolveSubsection(nil, for: initialSection)
        }
        .onChange(of: selectedSubsection) { _, subsection in
            selectionChanged(subsection)
        }
    }

    func closeSettings() {
        close()
    }

    private static func resolveSubsection(
        _ subsection: AppSettingsSubsection?,
        for section: AppSettingsSection?
    ) -> AppSettingsSubsection? {
        guard let section else { return nil }
        guard let subsection, section.subsections.contains(subsection) else {
            return section.defaultSubsection
        }
        return subsection
    }
}
