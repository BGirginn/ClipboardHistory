import Foundation
import SQLite3

extension StorageService {
    func migrateEncryption(items: [ClipboardItem], mode _: EncryptionMode) throws {
        try ensureInitialized()
        var originals: [ClipboardItem] = []
        var migrated: [ClipboardItem] = []
        var createdFiles: [(URL, String, Bool)] = []

        do {
            for original in items {
                let shouldEncrypt = false
                guard shouldEncrypt != original.isEncrypted else { continue }
                originals.append(original)
                migrated.append(
                    try migratedItem(
                        from: original,
                        encrypt: shouldEncrypt,
                        createdFiles: &createdFiles
                    )
                )
            }

            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let statement = try prepareItemUpsertStatement()
                defer { sqlite3_finalize(statement) }
                let encoder = JSONEncoder()
                for item in migrated {
                    try insertOrReplace(item, using: statement, encoder: encoder)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch {
            for (directory, filename, encrypted) in createdFiles {
                try? fileManager.removeItem(
                    at: physicalURL(filename: filename, directory: directory, encrypted: encrypted)
                )
            }
            throw error
        }

        for original in originals {
            deletePhysicalAssets(for: original, encrypted: original.isEncrypted)
        }
    }

    private func migratedItem(
        from original: ClipboardItem,
        encrypt: Bool,
        createdFiles: inout [(URL, String, Bool)]
    ) throws -> ClipboardItem {
        var updated = original
        if let filename = original.imageFilename {
            guard let migrated = try migrateAsset(
                filename,
                in: imagesDirectory,
                sourceEncrypted: original.isEncrypted,
                destinationEncrypted: encrypt,
                required: true,
                createdFiles: &createdFiles
            ) else { throw DatabaseError.executionFailed("migration image unavailable") }
            updated.imageFilename = migrated
        }
        updated.assetFilenames = try original.assetFilenames.map { filename in
            guard let migrated = try migrateAsset(
                filename,
                in: imagesDirectory,
                sourceEncrypted: original.isEncrypted,
                destinationEncrypted: encrypt,
                required: true,
                createdFiles: &createdFiles
            ) else { throw DatabaseError.executionFailed("migration image unavailable") }
            return migrated
        }
        if let filename = original.thumbnailFilename {
            updated.thumbnailFilename = try migrateAsset(
                filename,
                in: thumbnailsDirectory,
                sourceEncrypted: original.isEncrypted,
                destinationEncrypted: encrypt,
                required: false,
                createdFiles: &createdFiles
            )
        }
        if let filename = original.payloadFilename {
            guard let migrated = try migrateAsset(
                filename,
                in: payloadsDirectory,
                sourceEncrypted: original.isEncrypted,
                destinationEncrypted: encrypt,
                required: true,
                createdFiles: &createdFiles
            ) else { throw DatabaseError.executionFailed("migration payload unavailable") }
            updated.payloadFilename = migrated
        }
        updated.isEncrypted = encrypt
        return updated
    }

    private func migrateAsset(
        _ filename: String,
        in directory: URL,
        sourceEncrypted: Bool,
        destinationEncrypted: Bool,
        required: Bool,
        createdFiles: inout [(URL, String, Bool)]
    ) throws -> String? {
        guard let data = loadFile(
            filename: filename,
            directory: directory,
            isEncrypted: sourceEncrypted
        ) else {
            if required { throw DatabaseError.executionFailed("migration source asset unavailable") }
            return nil
        }
        let migratedFilename = "migration-\(UUID().uuidString.lowercased())-\(filename)"
        guard storeFile(
            data: data,
            logicalFilename: migratedFilename,
            directory: directory,
            encrypt: destinationEncrypted
        ) else {
            throw DatabaseError.executionFailed("migration destination asset unavailable")
        }
        createdFiles.append((directory, migratedFilename, destinationEncrypted))
        guard let verified = loadFile(
            filename: migratedFilename,
            directory: directory,
            isEncrypted: destinationEncrypted
        ), HashUtility.sha256(data: verified) == HashUtility.sha256(data: data) else {
            throw DatabaseError.executionFailed("migration asset verification failed")
        }
        return migratedFilename
    }

    func cleanup(
        historyLimit: Int,
        retentionDays: Int,
        imageRetentionDays: Int,
        maximumStorageBytes: Int64,
        prefetchedItems: [ClipboardItem]? = nil
    ) -> CleanupReport {
        do {
            try ensureInitialized()
            let allItems: [ClipboardItem]
            if let prefetchedItems {
                allItems = prefetchedItems
            } else {
                allItems = try fetchAllItems()
            }
            let before = storageMetrics().totalBytes
            let now = Date.now
            let generalCutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
            let imageCutoff = now.addingTimeInterval(-Double(imageRetentionDays) * 86_400)
            var removalIDs = Set<UUID>()

            let unpinned = allItems.filter { !$0.isPinned }
                .sorted { $0.creationDate > $1.creationDate }
            for item in unpinned.dropFirst(max(1, historyLimit)) {
                removalIDs.insert(item.id)
            }
            for item in unpinned {
                if item.creationDate < generalCutoff {
                    removalIDs.insert(item.id)
                }
                if item.type == .image || item.type == .imageGroup,
                   item.creationDate < imageCutoff {
                    removalIDs.insert(item.id)
                }
            }

            var currentBytes = try allItems.reduce(into: Int64(0)) { total, item in
                total += try reclaimableStorageCost(for: item)
            }
            if currentBytes > maximumStorageBytes {
                for item in unpinned.sorted(by: { ($0.lastUsedAt ?? $0.creationDate) < ($1.lastUsedAt ?? $1.creationDate) }) {
                    guard currentBytes > maximumStorageBytes else { break }
                    if removalIDs.insert(item.id).inserted {
                        currentBytes -= try reclaimableStorageCost(for: item)
                    }
                }
            }

            let removedItems = allItems.filter { removalIDs.contains($0.id) }
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for item in removedItems {
                    try deleteItemRecord(id: item.id)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
            for item in removedItems {
                deleteAssociatedFiles(for: item)
            }
            compactDatabaseAfterCleanup(
                removedItemCount: removedItems.count,
                originalItemCount: allItems.count
            )
            let after = storageMetrics().totalBytes
            return CleanupReport(
                removedItemCount: removedItems.count,
                reclaimedBytes: max(0, before - after)
            )
        } catch {
            AppLog.storage.error(
                "Retention cleanup failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return CleanupReport(removedItemCount: 0, reclaimedBytes: 0)
        }
    }

    func storageMetrics() -> StorageMetrics {
        StorageMetrics(
            databaseBytes: fileSize(at: databaseFile),
            imageBytes: directorySize(imagesDirectory),
            thumbnailBytes: directorySize(thumbnailsDirectory),
            payloadBytes: directorySize(payloadsDirectory)
        )
    }

    func reclaimableStorageCost(for item: ClipboardItem) throws -> Int64 {
        try logicalDatabaseSize(for: item.id) + associatedFileSize(for: item)
    }

    private func logicalDatabaseSize(for itemID: UUID) throws -> Int64 {
        let statement = try prepare("""
            SELECT
                COALESCE(length(id), 0) + COALESCE(length(type), 0) +
                COALESCE(length(textContent), 0) + COALESCE(length(imageFilename), 0) +
                COALESCE(length(thumbnailFilename), 0) + COALESCE(length(contentHash), 0) +
                COALESCE(length(contentSubtype), 0) +
                COALESCE(length(sourceApplicationBundleID), 0) +
                COALESCE(length(displayTitle), 0) + COALESCE(length(payloadFilename), 0) +
                COALESCE(length(assetFilenames), 0) + COALESCE(length(fileURLs), 0) +
                COALESCE(length(fileBookmarks), 0) + COALESCE(length(protectedMetadata), 0) +
                COALESCE(length(collectionID), 0) + COALESCE(length(pasteboardTypes), 0) + 112
            FROM ClipboardItems WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        try bind(itemID.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return max(0, sqlite3_column_int64(statement, 0))
    }

    private func compactDatabaseAfterCleanup(removedItemCount: Int, originalItemCount: Int) {
        guard removedItemCount > 0 else { return }
        do {
            try execute("PRAGMA wal_checkpoint(PASSIVE)")
            try execute("PRAGMA optimize")
            let substantialRemoval = removedItemCount >= 25
                && removedItemCount * 4 >= max(1, originalItemCount)
            if substantialRemoval, fileSize(at: databaseFile) >= 8 * 1_024 * 1_024 {
                try execute("PRAGMA wal_checkpoint(TRUNCATE)")
                try execute("VACUUM")
            }
        } catch {
            AppLog.storage.error(
                "Post-cleanup database compaction failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func migrationStatus() -> String {
        do {
            try ensureInitialized()
            if try settingValue(for: "jsonMigrationStatus") == "failed" {
                return String(localized: "SQLite schema \(Self.schemaVersion); legacy migration preserved after failure")
            }
            return try settingValue(for: "jsonMigrationCompleted") == "1"
                ? String(localized: "SQLite schema \(Self.schemaVersion); JSON migration complete")
                : String(localized: "SQLite schema \(Self.schemaVersion); no legacy migration")
        } catch {
            return String(localized: "Database unavailable")
        }
    }

    func close() {
        isClosed = true
        guard let database else { return }
        try? execute("PRAGMA wal_checkpoint(TRUNCATE)")
        sqlite3_close(database)
        self.database = nil
        isInitialized = false
    }

    nonisolated func imageURL(filename: String, isEncrypted: Bool = false) -> URL? {
        guard let filename = ManagedFilename(filename) else { return nil }
        return physicalURL(filename: filename.value, directory: imagesDirectory, encrypted: isEncrypted)
    }

    nonisolated func payloadURL(filename: String, isEncrypted: Bool = false) -> URL? {
        guard let filename = ManagedFilename(filename) else { return nil }
        return physicalURL(filename: filename.value, directory: payloadsDirectory, encrypted: isEncrypted)
    }

}
