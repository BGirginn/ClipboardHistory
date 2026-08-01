import AppKit

@MainActor
struct SystemClipboardDragProvider: ClipboardDragProviding {
    func make(for item: ClipboardItem, storage: StorageService) -> NSItemProvider {
        ClipboardDragProviderFactory.make(for: item, storage: storage)
    }
}
