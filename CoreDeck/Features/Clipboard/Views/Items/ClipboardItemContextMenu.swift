import SwiftUI

struct ClipboardItemContextMenu: View {
    let item: ClipboardItem
    let actions: ClipboardItemActions

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc", action: commands.copy)
        Button("Paste to Active App", systemImage: "arrow.right.to.line", action: commands.paste)
        Button("Paste as Plain Text", systemImage: "textformat", action: commands.pasteAsPlainText)
        Menu("Paste As", systemImage: "doc.on.clipboard") {
            ForEach(PasteRepresentation.allCases) { representation in
                ClipboardItemRepresentationMenuButton(
                    command: ClipboardItemRepresentationMenuCommand(
                        commands: commands,
                        representation: representation,
                        operation: .paste
                    )
                )
            }
        }
        Menu("Copy As", systemImage: "doc.on.doc") {
            ForEach(PasteRepresentation.allCases) { representation in
                ClipboardItemRepresentationMenuButton(
                    command: ClipboardItemRepresentationMenuCommand(
                        commands: commands,
                        representation: representation,
                        operation: .copy
                    )
                )
            }
        }
        Button(
            item.isPinned ? "Unpin" : "Pin",
            systemImage: item.isPinned ? "pin.slash" : "pin",
            action: commands.togglePin
        )
        Button(
            item.isSnippet ? "Remove from Snippets" : "Keep as Snippet",
            systemImage: item.isSnippet ? "text.badge.minus" : "text.badge.plus",
            action: commands.toggleSnippet
        )
        Menu("Move to Collection", systemImage: "folder") {
            Button("No Collection", action: commands.removeFromCollection)
            if !actions.collections.isEmpty {
                Divider()
                ForEach(actions.collections) { collection in
                    ClipboardItemCollectionMenuButton(
                        title: collection.name,
                        command: ClipboardItemCollectionMenuCommand(
                            commands: commands,
                            collectionID: collection.id
                        )
                    )
                }
            }
        }
        if actions.pasteStackItemIDs.contains(item.id) {
            Button(
                "Remove from Paste Stack",
                systemImage: "text.badge.minus",
                action: commands.removeFromPasteStack
            )
        } else {
            Button(
                "Add to Paste Stack",
                systemImage: "text.badge.plus",
                action: commands.addToPasteStack
            )
        }
        Button("Show Details", systemImage: "info.circle", action: commands.showDetails)

        if [.image, .imageGroup].contains(item.type) {
            Divider()
            Button("Reveal in Finder", systemImage: "folder", action: commands.reveal)
            Button("Export As PNG…", systemImage: "square.and.arrow.up", action: commands.exportPNG)
            Button("Export As JPEG…", systemImage: "square.and.arrow.up", action: commands.exportJPEG)
        } else if item.type == .files {
            Divider()
            Button("Reveal in Finder", systemImage: "folder", action: commands.reveal)
        }

        Divider()
        Button("Delete", systemImage: "trash", role: .destructive, action: commands.deleteItem)
    }

    private var commands: ClipboardItemMenuCommands {
        ClipboardItemMenuCommands(item: item, actions: actions)
    }
}
