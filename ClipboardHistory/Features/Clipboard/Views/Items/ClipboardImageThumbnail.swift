import AppKit
import SwiftUI

struct ClipboardImageThumbnail: View {
    let item: ClipboardItem
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let isLocked: Bool

    @State private var image: NSImage?
    @State private var didFail = false

    init(
        item: ClipboardItem,
        storage: StorageService,
        thumbnailService: ThumbnailService,
        isLocked: Bool,
        image: NSImage? = nil,
        didFail: Bool = false
    ) {
        self.item = item
        self.storage = storage
        self.thumbnailService = thumbnailService
        self.isLocked = isLocked
        _image = State(initialValue: image)
        _didFail = State(initialValue: didFail)
    }

    var body: some View {
        Group {
            if isLocked || item.isSensitive {
                Image(systemName: "eye.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 88, height: 64)
        .background(.background, in: .rect(cornerRadius: 6))
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: "\(item.id.uuidString)-\(isLocked)") {
            await loadThumbnail()
        }
    }

    func loadThumbnail() async {
        image = nil
        didFail = false
        guard !isLocked, !item.isSensitive else { return }
        guard let data = await thumbnailService.thumbnailData(for: item, storage: storage),
              !Task.isCancelled,
              let loaded = NSImage(data: data) else {
            if !Task.isCancelled { didFail = true }
            return
        }
        image = loaded
    }
}
