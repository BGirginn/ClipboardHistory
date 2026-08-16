import SwiftUI

struct AppSettingsContentView: View {
    let selectedSection: AppSettingsSection
    let selectedSubsection: AppSettingsSubsection
    @ObservedObject var viewModel: SettingsFeatureModel

    @ViewBuilder
    var body: some View {
        switch selectedSection {
        case .general:
            AppPreferencesView(
                viewModel: viewModel,
                selectedSubsection: selectedSubsection
            )
        case .menuBar:
            MenuBarSettingsView(
                model: viewModel.controlCenter,
                selectedSubsection: selectedSubsection
            )
        case .clipboard:
            ClipboardSettingsContentView(
                selectedSection: selectedSubsection.clipboardSection ?? .general,
                viewModel: viewModel
            )
        case .notes:
            NotesSettingsView(
                viewModel: viewModel,
                selectedSubsection: selectedSubsection
            )
        case .inputTools:
            InputToolsSettingsView(
                inputTools: viewModel.inputTools,
                selectedSubsection: selectedSubsection
            )
        case .systemMonitor:
            SystemMonitorSettingsView(
                controller: viewModel.systemMetrics,
                selectedSubsection: selectedSubsection
            )
        case .audioMixer:
            AudioMixerSettingsView(
                controller: viewModel.audioMixer,
                selectedSubsection: selectedSubsection
            )
        }
    }
}
