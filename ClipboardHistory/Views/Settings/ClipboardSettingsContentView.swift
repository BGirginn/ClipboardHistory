import SwiftUI

struct ClipboardSettingsContentView: View {
    let selectedSection: ClipboardSettingsSection
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    @ViewBuilder
    var body: some View {
        switch selectedSection {
        case .general:
            ClipboardSettingsGeneralView(viewModel: viewModel)
        case .privacy:
            ClipboardSettingsPrivacyView(viewModel: viewModel)
        case .security:
            ClipboardSettingsSecurityView(viewModel: viewModel)
        case .storage:
            ClipboardSettingsStorageView(viewModel: viewModel)
        case .advanced:
            ClipboardSettingsAdvancedView(viewModel: viewModel)
        }
    }
}
