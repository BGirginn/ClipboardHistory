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
                    title: String(localized: "Open Notes"),
                    systemImage: "note.text",
                    helpText: String(localized: "Open a new note"),
                    accessibilityIdentifier: "header.notes",
                    accessibilityValue: viewModel.isLocked ? "Unavailable" : "Available",
                    isDisabled: viewModel.isLocked,
                    action: viewModel.showNotesQuickEditor
                )

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
                    systemImage: "arrow.right.to.line.compact",
                    helpText: "Ignore only the next clipboard change",
                    accessibilityIdentifier: "header.ignoreNext",
                    accessibilityValue: viewModel.isIgnoringNextCopy ? "Armed" : "Available",
                    isActive: viewModel.isIgnoringNextCopy,
                    tint: .orange,
                    action: viewModel.toggleIgnoreNextCopy
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
                    Button("Older Than 1 Hour", action: cleanOlderThanOneHour)
                    Button("Older Than 1 Day", action: cleanOlderThanOneDay)
                    Button("Older Than 1 Week", action: cleanOlderThanOneWeek)
                    Button("Older Than 30 Days", action: cleanOlderThanThirtyDays)
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

    func toggleLock() {
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
        }
    }

    func showSettings() {
        viewModel.panelSection = .settings
    }

    func cleanOlderThanOneHour() {
        viewModel.requestAgeCleanup(olderThan: 3_600)
    }

    func cleanOlderThanOneDay() {
        viewModel.requestAgeCleanup(olderThan: 86_400)
    }

    func cleanOlderThanOneWeek() {
        viewModel.requestAgeCleanup(olderThan: 604_800)
    }

    func cleanOlderThanThirtyDays() {
        viewModel.requestAgeCleanup(olderThan: 2_592_000)
    }
}
