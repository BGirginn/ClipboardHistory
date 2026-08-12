import AppKit
import SwiftUI

@MainActor
struct ClipboardPanelItemActionRouter {
    let viewModel: ClipboardHistoryViewModel
    let commandModifierIsPressed: () -> Bool

    init(
        viewModel: ClipboardHistoryViewModel,
        commandModifierIsPressed: @escaping () -> Bool = {
            NSEvent.modifierFlags.contains(.command)
        }
    ) {
        self.viewModel = viewModel
        self.commandModifierIsPressed = commandModifierIsPressed
    }

    func selectAndCopy(_ item: ClipboardItem) {
        if commandModifierIsPressed() {
            viewModel.toggleSelection(item)
        } else {
            viewModel.selectOnly(item)
            viewModel.restore(item)
        }
    }

    func copy(_ item: ClipboardItem) {
        viewModel.restore(item)
    }

    func paste(_ item: ClipboardItem) {
        viewModel.paste(item)
    }

    func copyAs(_ item: ClipboardItem, _ representation: PasteRepresentation) {
        viewModel.copy(item, as: representation)
    }

    func pasteAs(_ item: ClipboardItem, _ representation: PasteRepresentation) {
        viewModel.paste(item, as: representation)
    }

    func togglePin(_ item: ClipboardItem) {
        viewModel.togglePin(item)
    }

    func toggleSnippet(_ item: ClipboardItem) {
        viewModel.toggleSnippet(item)
    }

    func move(_ item: ClipboardItem, _ collectionID: UUID?) {
        viewModel.move(item, to: collectionID)
    }

    func addToPasteStack(_ item: ClipboardItem) {
        viewModel.addToPasteStack(item)
    }

    func removeFromPasteStack(_ item: ClipboardItem) {
        viewModel.removeFromPasteStack(item)
    }

    func dragProvider(_ item: ClipboardItem) -> NSItemProvider {
        if item.isSensitive {
            viewModel.revealSensitiveDetails(item)
            return NSItemProvider()
        }
        return viewModel.dragProvider.make(for: item, storage: viewModel.storage)
    }

    func showDetails(_ item: ClipboardItem) {
        viewModel.showDetails(item)
    }

    func reveal(_ item: ClipboardItem) {
        viewModel.reveal(item)
    }

    func exportImage(_ item: ClipboardItem, _ asJPEG: Bool) {
        viewModel.exportImage(item, asJPEG: asJPEG)
    }

    func delete(_ item: ClipboardItem) {
        viewModel.delete(item)
    }

    func menuCommandDidRun() {
        viewModel.notifyMenuCommandDidRun()
    }
}
