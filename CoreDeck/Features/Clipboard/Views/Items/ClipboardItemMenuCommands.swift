import Foundation

struct ClipboardItemMenuCommands {
    let item: ClipboardItem
    let actions: ClipboardItemActions

    func copy() {
        beginCommand()
        actions.copy(item)
    }

    func paste() {
        beginCommand()
        actions.paste(item)
    }

    func pasteAsPlainText() {
        pasteAs(.plainText)
    }

    func pasteAs(_ representation: PasteRepresentation) {
        beginCommand()
        actions.pasteAs(item, representation)
    }

    func copyAs(_ representation: PasteRepresentation) {
        beginCommand()
        actions.copyAs(item, representation)
    }

    func togglePin() {
        beginCommand()
        actions.togglePin(item)
    }

    func toggleSnippet() {
        beginCommand()
        actions.toggleSnippet(item)
    }

    func removeFromCollection() {
        move(to: nil)
    }

    func move(to collectionID: UUID?) {
        beginCommand()
        actions.moveToCollection(item, collectionID)
    }

    func addToPasteStack() {
        beginCommand()
        actions.addToPasteStack(item)
    }

    func removeFromPasteStack() {
        beginCommand()
        actions.removeFromPasteStack(item)
    }

    func showDetails() {
        beginCommand()
        actions.showDetails(item)
    }

    func reveal() {
        beginCommand()
        actions.reveal(item)
    }

    func exportPNG() {
        exportImage(asJPEG: false)
    }

    func exportJPEG() {
        exportImage(asJPEG: true)
    }

    func deleteItem() {
        beginCommand()
        actions.delete(item)
    }

    private func exportImage(asJPEG: Bool) {
        beginCommand()
        actions.exportImage(item, asJPEG)
    }

    private func beginCommand() {
        actions.menuCommandDidRun()
    }
}
