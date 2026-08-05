import SwiftUI

struct ClipboardQuickSelectionButton: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let index: Int

    var body: some View {
        Button(action: restore) {
            EmptyView()
        }
        .keyboardShortcut(
            KeyEquivalent(Character(String(index + 1))),
            modifiers: .command
        )
    }

    func restore() {
        viewModel.restoreVisibleItem(at: index)
    }
}
