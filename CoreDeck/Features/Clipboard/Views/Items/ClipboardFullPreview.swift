import SwiftUI

struct ClipboardFullPreview: View {
    let item: ClipboardItem
    let storage: StorageService

    @State private var image: NSImage?

    init(item: ClipboardItem, storage: StorageService, image: NSImage? = nil) {
        self.item = item
        self.storage = storage
        _image = State(initialValue: image)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 300)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .task(id: item.id) {
            await loadImage()
        }
        .overlay {
            if item.type == .pdf && image == nil {
                Label("Press Space for Quick Look", systemImage: "doc.richtext")
                    .foregroundStyle(.secondary)
            }
        }
    }

    func loadImage() async {
        let data: Data?
        if item.type == .pdf {
            data = nil
        } else if let filename = item.imageFilename ?? item.assetFilenames.first {
            data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted)
        } else {
            data = nil
        }
        guard !Task.isCancelled else { return }
        image = data.flatMap(NSImage.init(data:))
    }
}
