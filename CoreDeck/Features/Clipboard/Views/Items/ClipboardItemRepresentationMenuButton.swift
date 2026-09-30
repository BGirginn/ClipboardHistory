import SwiftUI

struct ClipboardItemRepresentationMenuButton: View {
    let command: ClipboardItemRepresentationMenuCommand

    var body: some View {
        Button(command.representation.title, action: command.perform)
    }
}
