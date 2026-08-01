import SwiftUI

struct ClipboardSearchField: View {
    @Binding var text: String
    let focusRequest: Int
    let focusChanged: (Bool) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search history or use field filters…", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityHint("Filter by app:, type:, tag:, collection:, ocr:, after:, or before:")
                .accessibilityIdentifier("search.field")
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill", action: clearSearch)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: .rect(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .task(id: focusRequest) { isFocused = true }
        .task(id: isFocused) { focusChanged(isFocused) }
    }

    private func clearSearch() {
        text = ""
    }
}
