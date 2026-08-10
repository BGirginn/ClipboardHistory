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
        case .security:
            ClipboardSettingsSecurityView(viewModel: viewModel)
        case .storage:
            ClipboardSettingsStorageView(viewModel: viewModel)
        case .systemMonitor:
            SystemMonitorSettingsView(viewModel: viewModel)
        case .audio:
            AudioMixerSettingsView(viewModel: viewModel)
        case .advanced:
            ClipboardSettingsAdvancedView(viewModel: viewModel)
        }
    }
}
