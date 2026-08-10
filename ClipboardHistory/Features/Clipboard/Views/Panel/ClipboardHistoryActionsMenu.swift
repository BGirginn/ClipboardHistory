import SwiftUI

struct ClipboardHistoryActionsMenu: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            if viewModel.isApplicationLockEnabled {
                Button(
                    viewModel.isLocked ? "Unlock Clipboard History" : "Lock Clipboard History",
                    systemImage: viewModel.isLocked ? "lock.open" : "lock",
                    action: toggleLock
                )
                Divider()
            }

            Button(
                viewModel.isPrivateMode ? "Disable Private Mode" : "Enable Private Mode",
                systemImage: viewModel.isPrivateMode ? "eye" : "eye.slash",
                action: togglePrivateMode
            )
            Divider()

            Button(
                "Clear All History",
                systemImage: "trash",
                role: .destructive,
                action: clearHistory
            )
            .disabled(viewModel.items.isEmpty)

            Menu("Clean History by Age", systemImage: "calendar.badge.minus") {
                Button("Older Than 1 Hour") { requestAgeCleanup(3_600) }
                Button("Older Than 1 Day") { requestAgeCleanup(86_400) }
                Button("Older Than 1 Week") { requestAgeCleanup(604_800) }
                Button("Older Than 30 Days") { requestAgeCleanup(2_592_000) }
            }
            .disabled(viewModel.items.isEmpty)
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .frame(
            width: ClipboardPanelLayout.compactControlSize,
            height: ClipboardPanelLayout.compactControlSize
        )
        .help("More")
        .accessibilityIdentifier("header.actions")
    }

    func toggleLock() {
        markMenuCommand()
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
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

    func requestAgeCleanup(_ interval: TimeInterval) {
        markMenuCommand()
        viewModel.requestAgeCleanup(olderThan: interval)
    }

    func markMenuCommand() {
        viewModel.menuCommandDidRun?()
    }
}
