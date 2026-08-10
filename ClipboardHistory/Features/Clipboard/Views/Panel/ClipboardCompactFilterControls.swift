import SwiftUI

struct ClipboardCompactFilterControls: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Menu(viewModel.settings.selectedFilter.title, systemImage: "line.3.horizontal.decrease") {
                Picker("Filter", selection: $viewModel.settings.selectedFilter) {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter")
            .accessibilityValue(viewModel.settings.selectedFilter.title)
            .accessibilityIdentifier("filter.menu")

            Spacer(minLength: 0)

            ClipboardSortMenu(viewModel: viewModel)
        }
    }
}
