import Foundation

@MainActor
protocol QuickLookPresenting: AnyObject {
    func show(item: ClipboardItem, storage: StorageService)
    func close()
}
