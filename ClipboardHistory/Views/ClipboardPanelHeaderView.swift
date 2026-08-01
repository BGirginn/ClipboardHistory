import SwiftUI

struct ClipboardPanelHeaderView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard History")
                        .font(.headline)
                    Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "item" : "items")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if viewModel.isApplicationLockEnabled {
                    ClipboardHeaderActionButton(
                        title: viewModel.isLocked ? "Unlock Clipboard History" : "Lock Clipboard History",
                        systemImage: viewModel.isLocked ? "lock.fill" : "lock.open",
                        helpText: viewModel.isLocked
                            ? "Authenticate with Touch ID or your Mac login password to unlock clipboard previews"
                            : "Lock clipboard previews",
                        accessibilityIdentifier: "header.lock",
                        accessibilityValue: viewModel.isLocked ? "Locked" : "Unlocked",
                        isActive: viewModel.isLocked,
                        action: toggleLock
                    )
                }

                ClipboardHeaderActionButton(
                    title: viewModel.isPrivateMode ? "Disable Private Mode" : "Enable Private Mode",
                    systemImage: viewModel.isPrivateMode ? "eye.slash.fill" : "eye",
                    helpText: viewModel.isPrivateMode
                        ? "Resume clipboard recording"
                        : "Stop recording new clipboard items",
                    accessibilityIdentifier: "header.privateMode",
                    accessibilityValue: viewModel.isPrivateMode ? "Enabled" : "Disabled",
                    isActive: viewModel.isPrivateMode,
                    tint: .orange,
                    action: viewModel.togglePrivateMode
                )

                ClipboardHeaderActionButton(
                    title: "Ignore Next Copy",
                    systemImage: "eye.slash",
                    helpText: "Ignore only the next clipboard change",
                    accessibilityIdentifier: "header.ignoreNext",
                    accessibilityValue: "Available",
                    action: viewModel.ignoreNextCopy
                )

                ClipboardHeaderActionButton(
                    title: "Clear Clipboard History",
                    systemImage: "trash",
                    helpText: "Clear clipboard history",
                    accessibilityIdentifier: "header.clear",
                    accessibilityValue: viewModel.items.isEmpty ? "Unavailable" : "Available",
                    isDisabled: viewModel.items.isEmpty,
                    action: viewModel.clearHistory
                )

                Menu("Clean History by Age", systemImage: "calendar.badge.minus") {
                    Button("Older Than 1 Hour") {
                        viewModel.requestAgeCleanup(olderThan: 3_600)
                    }
                    Button("Older Than 1 Day") {
                        viewModel.requestAgeCleanup(olderThan: 86_400)
                    }
                    Button("Older Than 1 Week") {
                        viewModel.requestAgeCleanup(olderThan: 604_800)
                    }
                    Button("Older Than 30 Days") {
                        viewModel.requestAgeCleanup(olderThan: 2_592_000)
                    }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Clean unpinned history by age")
                .accessibilityLabel("Clean History by Age")

                ClipboardHeaderActionButton(
                    title: "Open Settings",
                    systemImage: "gearshape",
                    helpText: "Open settings",
                    accessibilityIdentifier: "header.settings",
                    accessibilityValue: "Available",
                    action: showSettings
                )
            }

            if viewModel.isLocked || viewModel.isPaused {
                ClipboardPanelStatusView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toggleLock() {
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
        }
    }

    private func showSettings() {
        viewModel.isShowingSettings = true
    }
}
