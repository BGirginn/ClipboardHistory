import Foundation

@MainActor
protocol ClipboardWriting: Sendable {
    var changeCount: Int { get }

    func write(
        content: ClipboardContent,
        representation: PasteRepresentation
    ) async -> Bool

    func write(
        item: ClipboardItem,
        storage: StorageService,
        representation: PasteRepresentation
    ) async -> Bool
}
