import SwiftUI

struct ClipboardHistoryListView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let reduceMotion: Bool

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                ClipboardEmptyStateView()
            } else if viewModel.pinnedItems.isEmpty && viewModel.recentItems.isEmpty {
                ClipboardFilteredEmptyStateView(hasSearch: !viewModel.searchText.isEmpty)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                            if !viewModel.pinnedItems.isEmpty {
                                Section {
                                    ForEach(viewModel.pinnedItems) { item in
                                        ClipboardItemRow(item: item, viewModel: viewModel)
                                            .id(item.id)
                                    }
                                } header: {
                                    ClipboardSectionHeader(title: "Pinned", systemImage: "pin.fill")
                                }
                            }
                            if !viewModel.recentItems.isEmpty {
                                Section {
                                    ForEach(viewModel.recentItems) { item in
                                        ClipboardItemRow(item: item, viewModel: viewModel)
                                            .id(item.id)
                                    }
                                } header: {
                                    ClipboardSectionHeader(title: "Recent", systemImage: "clock")
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: viewModel.selectedItemID) { selectedID in
                        guard let selectedID else { return }
                        if reduceMotion {
                            proxy.scrollTo(selectedID, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}
