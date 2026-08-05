import SwiftUI

struct ClipboardItemRowContent: View {
    let item: ClipboardItem
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let isLocked: Bool

    var body: some View {
        switch item.type {
        case .text, .richText:
            TextClipboardItemRow(item: item, isLocked: isLocked)
        case .image, .imageGroup:
            ImageClipboardItemRow(
                item: item,
                storage: storage,
                thumbnailService: thumbnailService,
                isLocked: isLocked
            )
        case .pdf, .files:
            DocumentClipboardItemRow(
                item: item,
                storage: storage,
                thumbnailService: thumbnailService,
                isLocked: isLocked
            )
        }
    }
}
