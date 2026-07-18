import SwiftUI

struct ClipboardFilterBar: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("Filter", selection: $viewModel.settings.selectedFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityIdentifier("filter.picker")

            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort Order", selection: $viewModel.settings.selectedSortMode) {
                    ForEach(ClipboardSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("sort.menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
