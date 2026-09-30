import Foundation

struct StorageRecoveryImportResult: Equatable, Sendable {
    let importedItemCount: Int
    let importedNoteCount: Int
    let rollbackBackupURL: URL?

    init(
        importedItemCount: Int,
        importedNoteCount: Int = 0,
        rollbackBackupURL: URL?
    ) {
        self.importedItemCount = importedItemCount
        self.importedNoteCount = importedNoteCount
        self.rollbackBackupURL = rollbackBackupURL
    }
}
