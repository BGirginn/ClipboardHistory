import AppKit
import Foundation

struct ClipboardItemActions {
    let selectAndCopy: (ClipboardItem) -> Void
    let copy: (ClipboardItem) -> Void
    let paste: (ClipboardItem) -> Void
    let copyAs: (ClipboardItem, PasteRepresentation) -> Void
    let pasteAs: (ClipboardItem, PasteRepresentation) -> Void
    let togglePin: (ClipboardItem) -> Void
    let toggleSnippet: (ClipboardItem) -> Void
    let moveToCollection: (ClipboardItem, UUID?) -> Void
    let collections: [ClipboardCollection]
    let addToPasteStack: (ClipboardItem) -> Void
    let removeFromPasteStack: (ClipboardItem) -> Void
    let pasteStackItemIDs: Set<UUID>
    let dragProvider: (ClipboardItem) -> NSItemProvider
    let showDetails: (ClipboardItem) -> Void
    let reveal: (ClipboardItem) -> Void
    let exportImage: (ClipboardItem, Bool) -> Void
    let delete: (ClipboardItem) -> Void
    let menuCommandDidRun: () -> Void
}
