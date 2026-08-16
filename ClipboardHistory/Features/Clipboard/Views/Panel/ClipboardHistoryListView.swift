import SwiftUI

struct ClipboardHistoryListView: View {
    let isHistoryEmpty: Bool
    let pinnedItems: [ClipboardItem]
    let recentItems: [ClipboardItem]
    let selectedItemID: UUID?
    let selectedItemIDs: Set<UUID>
    let copiedItemID: UUID?
    let hasSearch: Bool
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let actions: ClipboardItemActions
    let reduceMotion: Bool

    var body: some View {
        Group {
            if isHistoryEmpty {
                ClipboardEmptyStateView()
            } else if pinnedItems.isEmpty && recentItems.isEmpty {
                ClipboardFilteredEmptyStateView(hasSearch: hasSearch)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                            if !pinnedItems.isEmpty {
                                Section {
                                    ClipboardItemRows(
                                        items: pinnedItems,
                                        selectedItemID: selectedItemID,
                                        selectedItemIDs: selectedItemIDs,
                                        copiedItemID: copiedItemID,
                                        storage: storage,
                                        thumbnailService: thumbnailService,
                                        actions: actions
                                    )
                                } header: {
                                    ClipboardSectionHeader(title: "Pinned", systemImage: "pin.fill")
                                }
                            }
                            if !recentItems.isEmpty {
                                Section {
                                    ClipboardItemRows(
                                        items: recentItems,
                                        selectedItemID: selectedItemID,
                                        selectedItemIDs: selectedItemIDs,
                                        copiedItemID: copiedItemID,
                                        storage: storage,
                                        thumbnailService: thumbnailService,
                                        actions: actions
                                    )
                                } header: {
                                    ClipboardSectionHeader(title: "Recent", systemImage: "clock")
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: selectedItemID) { _, selectedID in
                        guard let selectedID else { return }
                        Self.scrollToSelected(reduceMotion: reduceMotion) {
                                proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    static func scrollToSelected(reduceMotion: Bool, action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeOut(duration: 0.12), action)
        }
    }
}
