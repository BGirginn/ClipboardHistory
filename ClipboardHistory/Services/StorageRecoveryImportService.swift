import Foundation

actor StorageRecoveryImportService {
    private let fileSystem: any MigrationFileSystem
    private let exportImportService: ExportImportService

    init(
        fileSystem: any MigrationFileSystem = LocalMigrationFileSystem(),
        exportImportService: ExportImportService = ExportImportService()
    ) {
        self.fileSystem = fileSystem
        self.exportImportService = exportImportService
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL,
        keyProvider: any MasterKeyProvider = KeychainMasterKeyProvider.active
    ) async throws -> StorageRecoveryImportResult {
        guard !password.isEmpty else { throw ExportImportError.passwordRequired }
        let destination = destinationDirectory.standardizedFileURL
        if fileSystem.fileExists(at: destination),
           try fileSystem.isSymbolicLink(at: destination) {
            throw ExportImportError.unsafePath
        }
        let parent = destination.deletingLastPathComponent()
        try fileSystem.createDirectory(at: parent)
        let staging = parent.appending(
            path: ".ClipboardHistory-recovery-import-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let backupRoot = parent.appending(
            path: "ClipboardHistory-Rollback-Backups",
            directoryHint: .isDirectory
        )
        let backup = backupRoot.appending(
            path: "before-recovery-import-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        var movedExistingData = false

        do {
            let stagingStorage = StorageService(
                baseDirectory: staging,
                keyProvider: keyProvider
            )
            let report: ImportReport
            do {
                report = try await exportImportService.importArchiveAtomically(
                    from: encryptedArchive,
                    password: password,
                    storage: stagingStorage,
                    encryptionMode: .all
                )
                await stagingStorage.close()
            } catch {
                // SQLite WAL files must be closed before the staging tree is removed.
                await stagingStorage.close()
                throw error
            }

            if fileSystem.fileExists(at: destination) {
                try fileSystem.createDirectory(at: backupRoot)
                try fileSystem.moveItem(at: destination, to: backup)
                movedExistingData = true
            }
            do {
                try fileSystem.moveItem(at: staging, to: destination)
            } catch {
                if movedExistingData {
                    try? fileSystem.moveItem(at: backup, to: destination)
                }
                throw error
            }
            return StorageRecoveryImportResult(
                importedItemCount: report.importedCount,
                rollbackBackupURL: movedExistingData ? backup : nil
            )
        } catch {
            if fileSystem.fileExists(at: staging) {
                try? fileSystem.removeItem(at: staging)
            }
            throw error
        }
    }
}
