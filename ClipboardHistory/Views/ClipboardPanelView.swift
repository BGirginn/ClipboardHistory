import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var searchIsFocused = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingSettings {
                ClipboardSettingsView(viewModel: viewModel)
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
                Divider()
                ClipboardHistoryListView(viewModel: viewModel, reduceMotion: reduceMotion)
            }
        }
        .frame(width: 380, height: 500)
        .background(
            reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial)
        )
        .background(KeyboardEventMonitorView(handler: handleKeyEvent))
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $viewModel.isShowingClearConfirmation
        ) {
            Button("Clear All History", role: .destructive, action: viewModel.confirmClearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items and all associated files and thumbnails will also be removed.")
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

    private func updateSearchFocus(_ focused: Bool) {
        searchIsFocused = focused
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
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
}
