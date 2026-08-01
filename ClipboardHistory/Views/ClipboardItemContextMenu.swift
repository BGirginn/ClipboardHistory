import SwiftUI

struct ClipboardItemContextMenu: View {
    let item: ClipboardItem
    let actions: ClipboardItemActions

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") {
            perform { actions.copy(item) }
        }
        Button("Paste to Active App", systemImage: "arrow.right.to.line") {
            perform { actions.paste(item) }
        }
        Button("Paste as Plain Text", systemImage: "textformat") {
            perform { actions.pasteAs(item, .plainText) }
        }
        Menu("Paste As", systemImage: "doc.on.clipboard") {
            ForEach(PasteRepresentation.allCases) { representation in
                Button(representation.title) {
                    perform { actions.pasteAs(item, representation) }
                }
            }
        }
        Menu("Copy As", systemImage: "doc.on.doc") {
            ForEach(PasteRepresentation.allCases) { representation in
                Button(representation.title) {
                    perform { actions.copyAs(item, representation) }
                }
            }
        }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
            perform { actions.togglePin(item) }
        }
        Button(
            item.isSnippet ? "Remove from Snippets" : "Keep as Snippet",
            systemImage: item.isSnippet ? "text.badge.minus" : "text.badge.plus"
        ) {
            perform { actions.toggleSnippet(item) }
        }
        Menu("Move to Collection", systemImage: "folder") {
            Button("No Collection") {
                perform { actions.moveToCollection(item, nil) }
            }
            if !actions.collections.isEmpty {
                Divider()
                ForEach(actions.collections) { collection in
                    Button(collection.name) {
                        perform { actions.moveToCollection(item, collection.id) }
                    }
                }
            }
        }
        if actions.pasteStackItemIDs.contains(item.id) {
            Button("Remove from Paste Stack", systemImage: "text.badge.minus") {
                perform { actions.removeFromPasteStack(item) }
            }
        } else {
            Button("Add to Paste Stack", systemImage: "text.badge.plus") {
                perform { actions.addToPasteStack(item) }
            }
        }
        Button("Show Details", systemImage: "info.circle") {
            perform { actions.showDetails(item) }
        }

        if [.image, .imageGroup].contains(item.type) {
            Divider()
            Button("Reveal in Finder", systemImage: "folder") {
                perform { actions.reveal(item) }
            }
            Button("Export As PNG…", systemImage: "square.and.arrow.up") {
                perform { actions.exportImage(item, false) }
            }
            Button("Export As JPEG…", systemImage: "square.and.arrow.up") {
                perform { actions.exportImage(item, true) }
            }
        } else if item.type == .files {
            Divider()
            Button("Reveal in Finder", systemImage: "folder") {
                perform { actions.reveal(item) }
            }
        }

        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            perform { actions.delete(item) }
        }
    }

    private func perform(_ action: () -> Void) {
        actions.menuCommandDidRun()
        action()
    }
}
