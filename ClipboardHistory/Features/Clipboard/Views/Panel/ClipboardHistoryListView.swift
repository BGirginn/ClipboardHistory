import SwiftUI

struct ClipboardHistoryListView: View {
    private static let initialRecentItemLimit = 200

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
    @State private var recentItemLimit = Self.initialRecentItemLimit

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
                                        items: Array(recentItems.prefix(recentItemLimit)),
                                        selectedItemID: selectedItemID,
                                        selectedItemIDs: selectedItemIDs,
                                        copiedItemID: copiedItemID,
                                        storage: storage,
                                        thumbnailService: thumbnailService,
                                        actions: actions
                                    )
                                    if recentItemLimit < recentItems.count {
                                        Button("Load More") {
                                            recentItemLimit = min(
                                                recentItems.count,
                                                recentItemLimit + Self.initialRecentItemLimit
                                            )
                                        }
                                        .buttonStyle(.borderless)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .accessibilityIdentifier("clipboard.load-more")
                                    }
                                } header: {
                                    ClipboardSectionHeader(title: "Recent", systemImage: "clock")
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: selectedItemID) { _, selectedID in
                        guard let selectedID else { return }
                        if let selectedIndex = recentItems.firstIndex(where: { $0.id == selectedID }),
                           selectedIndex >= recentItemLimit {
                            recentItemLimit = min(
                                recentItems.count,
                                selectedIndex + Self.initialRecentItemLimit
                            )
                            return
                        }
                        Self.scrollToSelected(reduceMotion: reduceMotion) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                    .onChange(of: recentItemLimit) { _, _ in
                        guard let selectedItemID else { return }
                        Self.scrollToSelected(reduceMotion: reduceMotion) {
                            proxy.scrollTo(selectedItemID, anchor: .center)
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
