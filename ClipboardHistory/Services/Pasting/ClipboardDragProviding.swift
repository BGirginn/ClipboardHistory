import AppKit

@MainActor
protocol ClipboardDragProviding {
    func make(for item: ClipboardItem, storage: StorageService) -> NSItemProvider
}
