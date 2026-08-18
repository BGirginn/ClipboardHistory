import SwiftUI

struct ClipboardHistoryActionsMenu: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button(
                viewModel.isPrivateMode ? "Disable Private Mode" : "Enable Private Mode",
                systemImage: viewModel.isPrivateMode ? "eye" : "eye.slash",
                action: togglePrivateMode
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: ClipboardPanelLayout.compactControlSize,
                height: ClipboardPanelLayout.compactControlSize
            )
            .help(viewModel.isPrivateMode ? "Disable Private Mode" : "Enable Private Mode")
            .accessibilityIdentifier("header.privateMode")

            Menu("Clean Clipboard History", systemImage: "eraser") {
                Button("Run Cleanup", systemImage: "sparkles", action: runCleanup)
                    .disabled(viewModel.items.isEmpty)

                Menu("Clean History by Age", systemImage: "calendar.badge.minus") {
                    Button("Older Than 1 Hour") { requestAgeCleanup(3_600) }
                    Button("Older Than 1 Day") { requestAgeCleanup(86_400) }
                    Button("Older Than 1 Week") { requestAgeCleanup(604_800) }
                    Button("Older Than 30 Days") { requestAgeCleanup(2_592_000) }
                }
                .disabled(viewModel.items.isEmpty)

                Divider()
                Button(
                    "Clear All History",
                    systemImage: "trash",
                    role: .destructive,
                    action: clearHistory
                )
                .disabled(viewModel.items.isEmpty)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .frame(
                width: ClipboardPanelLayout.compactControlSize,
                height: ClipboardPanelLayout.compactControlSize
            )
            .help("Clean Clipboard History")
            .accessibilityIdentifier("header.cleanup")
            .confirmationDialog(
                "Clear all clipboard history?",
                isPresented: $viewModel.isShowingClearConfirmation
            ) {
                Button(
                    "Clear All History",
                    role: .destructive,
                    action: viewModel.confirmClearHistory
                )
                Button("Cancel", role: .cancel, action: viewModel.cancelClearHistory)
            } message: {
                Text("Pinned items and all associated files and thumbnails will also be removed.")
            }
            .onChange(of: viewModel.isShowingClearConfirmation) { _, isPresented in
                if !isPresented { viewModel.clearHistoryConfirmationDidDismiss() }
            }
        }
    }

    func togglePrivateMode() {
        markMenuCommand()
        viewModel.togglePrivateMode()
    }

    func clearHistory() {
        markMenuCommand()
        viewModel.clearHistory()
    }

    func runCleanup() {
        markMenuCommand()
        Task { await viewModel.runRetentionCleanup() }
    }

    func requestAgeCleanup(_ interval: TimeInterval) {
        markMenuCommand()
        viewModel.requestAgeCleanup(olderThan: interval)
    }

    func markMenuCommand() {
        viewModel.menuCommandDidRun?()
    }
}
