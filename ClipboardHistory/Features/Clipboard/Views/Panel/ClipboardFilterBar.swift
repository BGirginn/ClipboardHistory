import SwiftUI

struct ClipboardFilterBar: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ClipboardSegmentedFilterControls(viewModel: viewModel)
            ClipboardCompactFilterControls(viewModel: viewModel)
        }
        .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
        .padding(.vertical, 7)
    }
}
