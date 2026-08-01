import Foundation
import SQLite3

extension StorageService {
    func migrateEncryption(items: [ClipboardItem], mode: EncryptionMode) {
        do {
            try ensureInitialized()
            for original in items {
                let shouldEncrypt = mode == .all || (mode == .sensitive && original.isSensitive)
                guard shouldEncrypt != original.isEncrypted else { continue }
                guard try rewriteAssets(for: original, encrypt: shouldEncrypt) else { continue }

                var updated = original
                updated.isEncrypted = shouldEncrypt
                try execute("BEGIN IMMEDIATE TRANSACTION")
                do {
                    try insertOrReplace(updated)
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
                deletePhysicalAssets(for: original, encrypted: original.isEncrypted)
            }
        } catch {
            AppLog.storage.error(
                "Encryption migration failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func cleanup(
        historyLimit: Int,
        retentionDays: Int,
        imageRetentionDays: Int,
        maximumStorageBytes: Int64
    ) -> CleanupReport {
        do {
            try ensureInitialized()
            let allItems = try fetchAllItems()
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

            var currentBytes = storageMetrics().totalBytes
            if currentBytes > maximumStorageBytes {
                for item in unpinned.sorted(by: { ($0.lastUsedAt ?? $0.creationDate) < ($1.lastUsedAt ?? $1.creationDate) }) {
                    guard currentBytes > maximumStorageBytes else { break }
                    removalIDs.insert(item.id)
                    currentBytes -= associatedFileSize(for: item)
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
