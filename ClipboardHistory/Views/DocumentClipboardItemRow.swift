import AppKit
import SwiftUI

struct DocumentClipboardItemRow: View {
    let item: ClipboardItem
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            if item.type == .pdf {
                ClipboardImageThumbnail(
                    item: item,
                    storage: storage,
                    thumbnailService: thumbnailService,
                    isLocked: isLocked
                )
            } else {
                fileIcon
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(isLocked ? "Preview hidden while locked" : item.displayTitle ?? title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(detail)
                    Text("•")
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

    private var fileIcon: some View {
        Group {
            if let path = item.fileURLs.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private var title: String { item.type == .pdf ? "PDF Document" : "Files" }

    private var detail: String {
        if item.type == .pdf {
            return item.pageCount.map { "\($0) pages" } ?? "PDF"
        }
        let missing = item.fileURLs.filter { !FileManager.default.fileExists(atPath: $0) }.count
        return missing == 0 ? "\(item.fileURLs.count) item(s)" : "\(missing) unavailable"
    }
}
