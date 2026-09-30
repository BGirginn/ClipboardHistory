import Foundation

struct ClipboardItemCollectionMenuCommand {
    let commands: ClipboardItemMenuCommands
    let collectionID: UUID

    func perform() {
        commands.move(to: collectionID)
    }
}
