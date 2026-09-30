import SwiftUI

struct ClipboardFilteredEmptyStateView: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "line.3.horizontal.decrease.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(hasSearch ? "No matching clipboard items" : "No items in this section.")
                .font(.headline)
            if hasSearch {
                Text("Try another search term.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier(hasSearch ? "empty.search" : "empty.filter")
    }
}
