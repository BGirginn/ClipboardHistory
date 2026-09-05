import Foundation

struct ClipboardSettingsState: Equatable {
    let collections: [ClipboardCollection]
    let pasteStackItemIDs: [UUID]
    let storageMetrics: StorageMetrics
    let migrationStatus: String
    let cleanupMessage: String?
    let globalShortcutError: String?
    let archiveStatusMessage: String?
    let errorMessage: String?
    let isPrivateMode: Bool
    let pauseUntil: Date?

    @MainActor
    init(clipboard: ClipboardHistoryViewModel) {
        collections = clipboard.collections
        pasteStackItemIDs = clipboard.pasteStackItemIDs
        storageMetrics = clipboard.storageMetrics
        migrationStatus = clipboard.migrationStatus
        cleanupMessage = clipboard.cleanupMessage
        globalShortcutError = clipboard.globalShortcutError
        archiveStatusMessage = clipboard.archiveStatusMessage
        errorMessage = clipboard.errorMessage
        isPrivateMode = clipboard.isPrivateMode
        pauseUntil = clipboard.pauseUntil
    }
}
