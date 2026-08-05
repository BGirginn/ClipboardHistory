import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: ClipboardSettingsSection

    init(
        viewModel: ClipboardHistoryViewModel,
        initialSection: ClipboardSettingsSection = .general
    ) {
        self.viewModel = viewModel
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            ClipboardSettingsHeaderView(
                selectedSection: $selectedSection,
                close: closeSettings
            )
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            ClipboardSettingsContentView(
                selectedSection: selectedSection,
                viewModel: viewModel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(selectedSection)
            .transition(.opacity)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.12),
            value: selectedSection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await viewModel.refreshStorageInformation() }
        .accessibilityIdentifier("clipboard.settings")
    }

    func closeSettings() {
        viewModel.isShowingSettings = false
    }
}
