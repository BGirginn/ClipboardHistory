import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel {
    func prepareForPanelPresentation() {
        isShowingSettings = false
        detailItem = nil
        if !searchText.isEmpty {
            searchText = ""
        }
    }

    func enforceUnpinnedHistoryLimit() async {
        let unpinned = items.filter { !$0.isPinned && temporaryContent[$0.id] == nil }
            .sorted { $0.creationDate > $1.creationDate }
        guard unpinned.count > settings.historyLimit else { return }
        for item in unpinned.dropFirst(settings.historyLimit) {
            items.removeAll { $0.id == item.id }
            pasteboardIdentityByItemID[item.id] = nil
            await finishDeleting(item)
        }
    }

    func refreshDisplayedItems() {
        var filtered = items.filter(matchesSearch)
        switch settings.selectedFilter {
        case .all:
            break
        case .text:
            filtered = filtered.filter { $0.type == .text || $0.type == .richText }
        case .images:
            filtered = filtered.filter { $0.type == .image || $0.type == .imageGroup }
        case .pinned:
            filtered = filtered.filter(\.isPinned)
        case .snippets:
            filtered = filtered.filter(\.isSnippet)
        }

        pinnedItems = filtered.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        let unpinned = filtered.filter { !$0.isPinned }
        switch settings.selectedSortMode {
        case .newestFirst:
            recentItems = unpinned.sorted { $0.creationDate > $1.creationDate }
        case .oldestFirst:
            recentItems = unpinned.sorted { $0.creationDate < $1.creationDate }
        case .recentlyUsed:
            recentItems = unpinned.sorted {
                ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
            }
        }

        let visibleIDs = Set((pinnedItems + recentItems).map(\.id))
        if selectedItemID.map({ !visibleIDs.contains($0) }) ?? true {
            selectedItemID = (pinnedItems + recentItems).first?.id
        }
        selectedItemIDs = selectedItemIDs.intersection(visibleIDs)
        if selectedItemIDs.isEmpty, let selectedItemID {
            selectedItemIDs = [selectedItemID]
        }
    }

    func matchesSearch(_ item: ClipboardItem) -> Bool {
        let query = ClipboardSearchQuery(searchText)
        guard !query.isEmpty else { return true }
        guard !item.isSensitive else { return false }
        return query.matches(item, collectionName: collectionName(for: item))
    }

    func collectionName(for item: ClipboardItem) -> String? {
        guard let collectionID = item.collectionID else { return nil }
        return collections.first(where: { $0.id == collectionID })?.name
    }

    static func normalizedTags(from input: String) -> [String] {
        var keys = Set<String>()
        return input
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { keys.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted }
    }

    func moveSelection(by offset: Int) {
        let visible = pinnedItems + recentItems
        guard !visible.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let selectedItemID,
              let currentIndex = visible.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = visible.first?.id
            return
        }
        let newIndex = min(max(0, currentIndex + offset), visible.count - 1)
        self.selectedItemID = visible[newIndex].id
    }

}
