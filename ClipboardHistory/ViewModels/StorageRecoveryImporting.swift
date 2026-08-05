import Foundation

protocol StorageRecoveryImporting: Sendable {
    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult
}
