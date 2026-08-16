import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject private var settings: AppSettings
    let backToHome: () -> Void
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        viewModel: ClipboardHistoryViewModel,
        backToHome: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.backToHome = backToHome
        self.openSettings = openSettings
        _settings = ObservedObject(wrappedValue: viewModel.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isStorageAvailable {
                ContentUnavailableView(
                    "Clipboard Storage Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Open Settings from Control Center to inspect or recover clipboard storage.")
                )
            } else {
                panelContent
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
        .background { quickSelectionShortcuts }
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
            Button("Save Anyway", action: viewModel.confirmSensitiveSave)
            Button("Keep Temporarily", role: .cancel, action: viewModel.keepSensitiveTemporarily)
        } message: {
            Text("Detection is local and may produce false positives. Temporary content is excluded from disk and search.")
        }
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

    private var panelContent: some View {
        Group {
            if let item = viewModel.detailItem {
                ClipboardDetailView(item: item, viewModel: viewModel)
            } else {
                ClipboardPanelHeaderView(
                    viewModel: viewModel,
                    backToHome: backToHome,
                    openSettings: openSettings
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
                    hasSearch: false,
                    storage: viewModel.storage,
                    thumbnailService: viewModel.thumbnailService,
                    actions: itemActions,
                    reduceMotion: reduceMotion
                )
            }
        }
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {
            viewModel.closePanel()
            return true
        }
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
