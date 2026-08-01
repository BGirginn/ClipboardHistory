import SwiftUI

struct ClipboardItemCollectionMenuButton: View {
    let title: String
    let command: ClipboardItemCollectionMenuCommand

    var body: some View {
        Button(title, action: command.perform)
    }
}
