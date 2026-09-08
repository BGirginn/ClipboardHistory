import SwiftUI

struct ClipboardSearchField: View {
    @ObservedObject var model: ClipboardHistoryViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search History", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityIdentifier("clipboard.searchField")
            Button("Close Search", systemImage: "xmark.circle.fill", action: model.toggleSearch)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("clipboard.closeSearch")
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
        .padding(.horizontal, AppDesign.horizontalPadding)
        .padding(.bottom, 8)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            isFocused = true
        }
        .onExitCommand { model.toggleSearch() }
    }
}
