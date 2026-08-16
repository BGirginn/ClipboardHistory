import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var viewModel: SettingsFeatureModel
    let initialSection: AppSettingsSection
    let initialSubsection: AppSettingsSubsection?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: AppSettingsSection
    @State private var selectedSubsection: AppSettingsSubsection

    init(
        viewModel: SettingsFeatureModel,
        initialSection: AppSettingsSection = .general,
        initialSubsection: AppSettingsSubsection? = nil,
        close: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.initialSection = initialSection
        self.initialSubsection = initialSubsection
        self.close = close
        _selectedSection = State(initialValue: initialSection)
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
                selectedSection: $selectedSection,
                selectedSubsection: $selectedSubsection,
                close: close
            )
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            AppSettingsContentView(
                selectedSection: selectedSection,
                selectedSubsection: selectedSubsection,
                viewModel: viewModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id("settings.content.\(selectedSubsection.rawValue)")
            .transition(.opacity)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.12),
            value: selectedSection
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.12),
            value: selectedSubsection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: initialSection) { _, section in
            selectedSection = section
            selectedSubsection = Self.resolveSubsection(
                initialSubsection,
                for: section
            )
        }
        .onChange(of: initialSubsection) { _, subsection in
            selectedSubsection = Self.resolveSubsection(
                subsection,
                for: selectedSection
            )
        }
        .onChange(of: selectedSection) { _, section in
            selectedSubsection = section.defaultSubsection
        }
    }

    func closeSettings() {
        close()
    }

    private static func resolveSubsection(
        _ subsection: AppSettingsSubsection?,
        for section: AppSettingsSection
    ) -> AppSettingsSubsection {
        guard let subsection, section.subsections.contains(subsection) else {
            return section.defaultSubsection
        }
        return subsection
    }
}
