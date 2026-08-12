import SwiftUI

struct ImageClipboardItemRow: View {
    let item: ClipboardItem
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ClipboardImageThumbnail(
                item: item,
                storage: storage,
                thumbnailService: thumbnailService,
                isLocked: isLocked
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if item.type == .imageGroup {
                        Text("\(item.assetFilenames.count) images")
                        Text("•")
                    }
                    Text(DateFormatting.timestamp(for: item.creationDate))
                    if item.isEncrypted {
                        Image(systemName: "lock.fill")
                            .accessibilityLabel("Encrypted")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private var title: String {
        if item.isSensitive { return "Sensitive content" }
        if isLocked { return "Preview hidden while locked" }
        return item.displayTitle ?? (item.type == .imageGroup ? "Images" : "Image")
    }
}
