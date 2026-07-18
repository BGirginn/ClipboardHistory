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
            TextField("Search clipboard", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
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
        .onChange(of: focusRequest) { _ in isFocused = true }
        .onChange(of: isFocused) { focused in focusChanged(focused) }
    }

    private func clearSearch() {
        text = ""
    }
}
