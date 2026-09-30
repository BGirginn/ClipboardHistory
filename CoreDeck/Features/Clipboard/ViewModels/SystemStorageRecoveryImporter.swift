import Foundation

struct SystemStorageRecoveryImporter: StorageRecoveryImporting {
    private let service: any StorageRecoveryImporting

    init(service: any StorageRecoveryImporting = StorageRecoveryImportService()) {
        self.service = service
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult {
        try await service.migrate(
            encryptedArchive: encryptedArchive,
            password: password,
            to: destinationDirectory
        )
    }
}
