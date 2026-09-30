import SwiftUI

struct ClipboardSettingsContentView: View {
    let selectedSection: ClipboardSettingsSection
    let viewModel: SettingsFeatureModel

    @ViewBuilder
    var body: some View {
        switch selectedSection {
        case .general:
            ClipboardSettingsGeneralView(viewModel: viewModel)
        case .privacy:
            ClipboardSettingsPrivacyView(viewModel: viewModel)
        case .storage:
            ClipboardSettingsStorageView(viewModel: viewModel)
        case .advanced:
            ClipboardSettingsAdvancedView(viewModel: viewModel)
        }
    }
}
