import Foundation

struct StorageRecoveryImportResult: Equatable, Sendable {
    let importedItemCount: Int
    let rollbackBackupURL: URL?
}
