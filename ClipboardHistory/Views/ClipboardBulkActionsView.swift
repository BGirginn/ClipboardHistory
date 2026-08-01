import SwiftUI

struct ClipboardBulkActionsView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack {
            Text("\(viewModel.selectedItemIDs.count) selected")
                .font(.caption.weight(.medium))
            Spacer()
            Button(
                "Add Selected to Paste Stack",
                systemImage: "square.stack.3d.up",
                action: addSelectedToPasteStack
            )
            .labelStyle(.iconOnly)
            .help("Add selected items to Paste Stack")
            Button(
                "Delete Selected",
                systemImage: "trash",
                role: .destructive,
                action: deleteSelectedItems
            )
            .labelStyle(.iconOnly)
            .help("Delete selected items")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .accessibilityIdentifier("bulkActions.bar")
    }

    func addSelectedToPasteStack() {
        viewModel.selectedItems.forEach(viewModel.addToPasteStack)
    }

    func deleteSelectedItems() {
        viewModel.deleteSelectedItems()
    }
}
