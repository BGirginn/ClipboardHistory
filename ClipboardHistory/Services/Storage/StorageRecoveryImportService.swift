import Foundation

actor StorageRecoveryImportService: StorageRecoveryImporting {
    private let fileSystem: any MigrationFileSystem
    private let exportImportService: ExportImportService
    private let keyProvider: any MasterKeyProvider
    private let noteKeyProvider: any MasterKeyProvider

    init(
        fileSystem: any MigrationFileSystem = LocalMigrationFileSystem(),
        exportImportService: ExportImportService = ExportImportService(),
        keyProvider: any MasterKeyProvider = KeychainMasterKeyProvider.active,
        noteKeyProvider: any MasterKeyProvider = KeychainMasterKeyProvider.notes
    ) {
        self.fileSystem = fileSystem
        self.exportImportService = exportImportService
        self.keyProvider = keyProvider
        self.noteKeyProvider = noteKeyProvider
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult {
        try await migrate(
            encryptedArchive: encryptedArchive,
            password: password,
            to: destinationDirectory,
            keyProvider: keyProvider,
            noteKeyProvider: noteKeyProvider
        )
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL,
        keyProvider: any MasterKeyProvider = KeychainMasterKeyProvider.active,
        noteKeyProvider: (any MasterKeyProvider)? = nil
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
                keyProvider: keyProvider,
                noteKeyProvider: noteKeyProvider ?? keyProvider
            )
            let report: ImportReport
            do {
                report = try await exportImportService.importArchiveAtomically(
                    from: encryptedArchive,
                    password: password,
                    storage: stagingStorage,
                    encryptionMode: .off
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
                var previousDatabaseRestored = !movedExistingData
                if movedExistingData {
                    do {
                        try fileSystem.moveItem(at: backup, to: destination)
                        previousDatabaseRestored = fileSystem.fileExists(at: destination)
                    } catch {
                        previousDatabaseRestored = false
                    }
                }
                throw StorageRecoveryError.installationFailed(
                    previousDatabaseRestored: previousDatabaseRestored,
                    underlyingDescription: error.localizedDescription
                )
            }
            return StorageRecoveryImportResult(
                importedItemCount: report.importedCount,
                importedNoteCount: report.importedNoteCount,
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
