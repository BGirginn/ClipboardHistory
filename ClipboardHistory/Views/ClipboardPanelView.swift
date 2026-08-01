import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var searchIsFocused: Bool

    init(viewModel: ClipboardHistoryViewModel, searchIsFocused: Bool = false) {
        self.viewModel = viewModel
        _settings = ObservedObject(wrappedValue: viewModel.settings)
        _searchIsFocused = State(initialValue: searchIsFocused)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isStorageAvailable {
                ClipboardStorageRecoveryView(viewModel: viewModel)
            } else if viewModel.isShowingSettings {
                ClipboardSettingsView(viewModel: viewModel)
            } else if viewModel.isLocked {
                VStack(spacing: 0) {
                    ClipboardPanelHeaderView(viewModel: viewModel)
                    Divider()
                    ClipboardLockedHistoryView(unlock: viewModel.unlock)
                }
            } else if let item = viewModel.detailItem {
                ClipboardDetailView(item: item, viewModel: viewModel)
            } else {
                ClipboardPanelHeaderView(viewModel: viewModel)
                ClipboardSearchField(
                    text: $viewModel.searchText,
                    focusRequest: viewModel.searchFocusRequest,
                    focusChanged: updateSearchFocus
                )
                ClipboardFilterBar(viewModel: viewModel)
                if viewModel.selectedItemIDs.count > 1 {
                    ClipboardBulkActionsView(viewModel: viewModel)
                }
                if !viewModel.pasteStackItems.isEmpty {
                    ClipboardPasteStackView(viewModel: viewModel)
                }
                Divider()
                ClipboardHistoryListView(
                    isHistoryEmpty: viewModel.items.isEmpty,
                    pinnedItems: viewModel.pinnedItems,
                    recentItems: viewModel.recentItems,
                    selectedItemID: viewModel.selectedItemID,
                    selectedItemIDs: viewModel.selectedItemIDs,
                    copiedItemID: viewModel.copiedItemID,
                    hasSearch: !viewModel.searchText.isEmpty,
                    isLocked: viewModel.isLocked,
                    storage: viewModel.storage,
                    thumbnailService: viewModel.thumbnailService,
                    actions: itemActions,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(
            minWidth: 340,
            idealWidth: 380,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 500,
            maxHeight: .infinity
        )
        .background(
            reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial)
        )
        .background(KeyboardEventMonitorView(handler: handleKeyEvent))
        .background(quickSelectionShortcuts)
        .preferredColorScheme(settings.appearance.colorScheme)
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $viewModel.isShowingClearConfirmation
        ) {
            Button("Clear All History", role: .destructive, action: viewModel.confirmClearHistory)
            Button("Cancel", role: .cancel, action: cancelDialog)
        } message: {
            Text("Pinned items and all associated files and thumbnails will also be removed.")
        }
        .confirmationDialog(
            "Delete unpinned items in this time range?",
            isPresented: $viewModel.isShowingAgeCleanupConfirmation
        ) {
            Button("Delete Matching Items", role: .destructive, action: viewModel.confirmAgeCleanup)
            Button("Cancel", role: .cancel, action: cancelDialog)
        } message: {
            Text("Pinned items are preserved. This cannot be undone.")
        }
        .confirmationDialog(
            "Save detected sensitive content?",
            isPresented: $viewModel.isShowingSensitiveSaveConfirmation
        ) {
            Button("Save Encrypted", action: viewModel.confirmSensitiveSave)
            Button("Keep Temporarily", role: .cancel, action: viewModel.keepSensitiveTemporarily)
        } message: {
            Text("Detection is local and may produce false positives. Temporary content is excluded from disk and search.")
        }
        .accessibilityIdentifier("clipboard.panel")
    }

    func updateSearchFocus(_ focused: Bool) {
        searchIsFocused = focused
    }

    private var itemActions: ClipboardItemActions {
        let router = ClipboardPanelItemActionRouter(viewModel: viewModel)
        return ClipboardItemActions(
            selectAndCopy: router.selectAndCopy,
            copy: router.copy,
            paste: router.paste,
            copyAs: router.copyAs,
            pasteAs: router.pasteAs,
            togglePin: router.togglePin,
            toggleSnippet: router.toggleSnippet,
            moveToCollection: router.move,
            collections: viewModel.collections,
            addToPasteStack: router.addToPasteStack,
            removeFromPasteStack: router.removeFromPasteStack,
            pasteStackItemIDs: Set(viewModel.pasteStackItemIDs),
            dragProvider: router.dragProvider,
            showDetails: router.showDetails,
            reveal: router.reveal,
            exportImage: router.exportImage,
            delete: router.delete,
            menuCommandDidRun: router.menuCommandDidRun
        )
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        handleKeyEvent(event, searchIsFocused: searchIsFocused)
    }

    func handleKeyEvent(_ event: NSEvent, searchIsFocused: Bool) -> Bool {
        guard !viewModel.isLocked else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            viewModel.focusSearch()
            return true
        }
        if event.keyCode == 53 {
            viewModel.closeOrClearSearch()
            return true
        }
        guard !searchIsFocused else { return false }

        if modifiers.contains(.command), event.keyCode == 51 {
            if modifiers.contains(.shift) {
                viewModel.clearHistory()
            } else {
                viewModel.deleteSelected()
            }
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125:
            viewModel.selectNext()
            return true
        case 126:
            viewModel.selectPrevious()
            return true
        case 36, 76:
            viewModel.restoreSelected()
            return true
        case 49:
            viewModel.previewSelected()
            return true
        default:
            return false
        }
    }

    private var quickSelectionShortcuts: some View {
        HStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { index in
                ClipboardQuickSelectionButton(viewModel: viewModel, index: index)
            }
        }
        .frame(width: 0, height: 0)
        .clipped()
        .accessibilityHidden(true)
    }

    func cancelDialog() {}
}
