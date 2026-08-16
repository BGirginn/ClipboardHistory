import SwiftUI

struct ClipboardItemRows: View {
    let items: [ClipboardItem]
    let selectedItemID: UUID?
    let selectedItemIDs: Set<UUID>
    let copiedItemID: UUID?
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let actions: ClipboardItemActions

    var body: some View {
        ForEach(items) { item in
            ClipboardItemRow(
                item: item,
                isSelected: selectedItemID == item.id || selectedItemIDs.contains(item.id),
                isCopied: copiedItemID == item.id,
                storage: storage,
                thumbnailService: thumbnailService,
                actions: actions
            )
            .equatable()
            .id(item.id)
        }
    }
}
