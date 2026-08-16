import SwiftUI

struct ClipboardSettingsContentView: View {
    let selectedSection: ClipboardSettingsSection
    @ObservedObject var viewModel: SettingsFeatureModel

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
