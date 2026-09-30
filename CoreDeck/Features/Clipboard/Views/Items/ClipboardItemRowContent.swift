import SwiftUI

struct ClipboardItemRowContent: View {
    let item: ClipboardItem
    let storage: StorageService
    let thumbnailService: ThumbnailService

    var body: some View {
        switch item.type {
        case .text, .richText:
            TextClipboardItemRow(item: item)
        case .image, .imageGroup:
            ImageClipboardItemRow(
                item: item,
                storage: storage,
                thumbnailService: thumbnailService
            )
        case .pdf, .files:
            DocumentClipboardItemRow(
                item: item,
                storage: storage,
                thumbnailService: thumbnailService
            )
        }
    }
}
