import SwiftUI

struct ClipboardItemContextMenu: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { viewModel.restore(item) }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
            viewModel.togglePin(item)
        }
        Button("Show Details", systemImage: "info.circle") { viewModel.showDetails(item) }

        if [.image, .imageGroup].contains(item.type) {
            Divider()
            Button("Reveal in Finder", systemImage: "folder") { viewModel.reveal(item) }
            Button("Export As PNG…", systemImage: "square.and.arrow.up") {
                viewModel.exportImage(item, asJPEG: false)
            }
            Button("Export As JPEG…", systemImage: "square.and.arrow.up") {
                viewModel.exportImage(item, asJPEG: true)
            }
        } else if item.type == .files {
            Divider()
            Button("Reveal in Finder", systemImage: "folder") { viewModel.reveal(item) }
        }

        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.delete(item) }
    }
}
