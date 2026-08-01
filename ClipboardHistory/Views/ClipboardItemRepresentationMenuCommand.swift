struct ClipboardItemRepresentationMenuCommand {
    enum Operation {
        case copy
        case paste
    }

    let commands: ClipboardItemMenuCommands
    let representation: PasteRepresentation
    let operation: Operation

    func perform() {
        switch operation {
        case .copy:
            commands.copyAs(representation)
        case .paste:
            commands.pasteAs(representation)
        }
    }
}
