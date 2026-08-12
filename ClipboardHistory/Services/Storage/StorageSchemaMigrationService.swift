import Foundation
import SQLite3

extension StorageService {
    func ensureInitialized() throws {
        guard !isClosed else { throw DatabaseError.closed }
        guard !isInitialized else { return }
        try createDirectoriesIfNeeded()
        try cleanupAbandonedStagingFiles()
        do {
            try openDatabase()
        } catch {
            if isCorruptionState {
                try attemptDatabaseRecovery()
            } else {
                throw error
            }
        }
        do {
            try createSchemaIfNeeded()
            try recoverInterruptedClearOperations()
            if try !databaseIntegrityIsValid() {
                try attemptDatabaseRecovery()
            }
        } catch {
            if isCorruptionState {
                try attemptDatabaseRecovery()
            } else {
                AppLog.storage.error(
                    "Database initialization failed; category=\(String(describing: type(of: error)), privacy: .public)"
                )
                throw error
            }
        }
        do {
            try migrateLegacyJSONIfNeeded()
        } catch {
            AppLog.storage.error(
                "Legacy migration failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            try preserveFailedLegacyMigration()
        }
        isInitialized = true
    }

    func openDatabase() throws {
        guard database == nil else { return }
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseFile.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(message)
        }
        database = handle
        sqlite3_busy_timeout(handle, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA synchronous=NORMAL")
    }

    func createSchemaIfNeeded() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS ClipboardItems (
                    id TEXT PRIMARY KEY NOT NULL,
                    type TEXT NOT NULL,
                    textContent BLOB,
                    imageFilename TEXT,
                    thumbnailFilename TEXT,
                    contentHash TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    lastUsedAt REAL,
                    pinnedAt REAL,
                    isPinned INTEGER NOT NULL DEFAULT 0,
                    useCount INTEGER NOT NULL DEFAULT 0,
                    contentSubtype TEXT NOT NULL DEFAULT 'unknown',
                    expiresAt REAL,
                    isSensitive INTEGER NOT NULL DEFAULT 0,
                    sourceApplicationBundleID TEXT,
                    storageVersion INTEGER NOT NULL DEFAULT 1,
                    displayTitle TEXT,
                    payloadFilename TEXT,
                    assetFilenames BLOB,
                    fileURLs BLOB,
                    fileBookmarks BLOB,
                    imageWidth INTEGER,
                    imageHeight INTEGER,
                    pageCount INTEGER,
                    fileSize INTEGER,
                    isEncrypted INTEGER NOT NULL DEFAULT 0
                )
                """)
            try execute("CREATE TABLE IF NOT EXISTS Settings (key TEXT PRIMARY KEY, value BLOB)")
            try execute("""
                CREATE TABLE IF NOT EXISTS SchemaMigrations (
                    version INTEGER PRIMARY KEY,
                    appliedAt REAL NOT NULL
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS idx_items_createdAt ON ClipboardItems(createdAt)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_lastUsedAt ON ClipboardItems(lastUsedAt)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_hash ON ClipboardItems(contentHash)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_type ON ClipboardItems(type)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_pinned ON ClipboardItems(isPinned, pinnedAt)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_expires ON ClipboardItems(expiresAt)")
            try execute("""
                INSERT OR IGNORE INTO SchemaMigrations(version, appliedAt)
                VALUES (1, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        try migrateToSchemaVersion2IfNeeded()
        try migrateToSchemaVersion3IfNeeded()
        try migrateToSchemaVersion4IfNeeded()
        try migrateToSchemaVersion5IfNeeded()
        try migrateToSchemaVersion6IfNeeded()
    }

    func migrateToSchemaVersion2IfNeeded() throws {
        guard try !hasSchemaMigration(version: 2) else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("ALTER TABLE ClipboardItems ADD COLUMN protectedMetadata BLOB")
            try execute("ALTER TABLE ClipboardItems ADD COLUMN collectionID TEXT")
            try execute("ALTER TABLE ClipboardItems ADD COLUMN isSnippet INTEGER NOT NULL DEFAULT 0")
            try execute("ALTER TABLE ClipboardItems ADD COLUMN pasteboardTypes BLOB")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_collection ON ClipboardItems(collectionID)")
            try execute("CREATE INDEX IF NOT EXISTS idx_items_snippet ON ClipboardItems(isSnippet)")
            try execute("""
                INSERT INTO SchemaMigrations(version, appliedAt)
                VALUES (2, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func migrateToSchemaVersion3IfNeeded() throws {
        guard try !hasSchemaMigration(version: 3) else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("""
                CREATE TABLE ClipboardCollections (
                    id TEXT PRIMARY KEY NOT NULL,
                    protectedName BLOB NOT NULL,
                    createdAt REAL NOT NULL,
                    sortOrder INTEGER NOT NULL DEFAULT 0
                )
                """)
            try execute("CREATE INDEX idx_collections_sort ON ClipboardCollections(sortOrder, createdAt)")
            try execute("""
                INSERT INTO SchemaMigrations(version, appliedAt)
                VALUES (3, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func migrateToSchemaVersion4IfNeeded() throws {
        guard try !hasSchemaMigration(version: 4) else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("""
                CREATE TABLE Notes (
                    id TEXT PRIMARY KEY NOT NULL,
                    protectedTitle BLOB NOT NULL,
                    protectedBody BLOB NOT NULL,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
                """)
            try execute("CREATE INDEX idx_notes_updated ON Notes(updatedAt DESC)")
            try execute("""
                INSERT INTO SchemaMigrations(version, appliedAt)
                VALUES (4, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func migrateToSchemaVersion5IfNeeded() throws {
        guard try !hasSchemaMigration(version: 5) else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let select = try prepare("""
                SELECT id, protectedMetadata, displayTitle, fileURLs, fileBookmarks
                FROM ClipboardItems
                """)
            defer { sqlite3_finalize(select) }
            let update = try prepare("""
                UPDATE ClipboardItems
                SET protectedMetadata = ?, fileURLs = NULL, fileBookmarks = NULL
                WHERE id = ?
                """)
            defer { sqlite3_finalize(update) }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            while sqlite3_step(select) == SQLITE_ROW {
                guard let id = textColumn(0, select) else {
                    throw DatabaseError.executionFailed("schema v5 item identifier is invalid")
                }
                let metadata: ClipboardProtectedMetadata
                if let encryptedMetadata = dataColumn(1, select) {
                    let plaintext = try encryptionService().decrypt(encryptedMetadata)
                    if let privateMetadata = try? decoder.decode(
                        ClipboardPrivateMetadataV2.self,
                        from: plaintext
                    ) {
                        metadata = privateMetadata.protectedMetadata
                    } else {
                        metadata = try decoder.decode(ClipboardProtectedMetadata.self, from: plaintext)
                    }
                } else {
                    metadata = ClipboardProtectedMetadata(displayTitle: textColumn(2, select))
                }
                let fileURLs = decodeArray(
                    [String].self,
                    from: dataColumn(3, select),
                    using: decoder
                ) ?? []
                let fileBookmarks = decodeArray(
                    [Data].self,
                    from: dataColumn(4, select),
                    using: decoder
                ) ?? []
                let privateMetadata = ClipboardPrivateMetadataV2(
                    protectedMetadata: metadata,
                    fileURLs: fileURLs,
                    fileBookmarks: fileBookmarks
                )
                let encrypted = try encryptionService().encrypt(try encoder.encode(privateMetadata))
                _ = sqlite3_reset(update)
                _ = sqlite3_clear_bindings(update)
                try bind(encrypted, at: 1, to: update)
                try bind(id, at: 2, to: update)
                guard sqlite3_step(update) == SQLITE_DONE else {
                    throw DatabaseError.executionFailed(databaseMessage())
                }
            }
            try execute("DROP INDEX IF EXISTS idx_items_text")
            try execute("""
                INSERT INTO SchemaMigrations(version, appliedAt)
                VALUES (5, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func migrateToSchemaVersion6IfNeeded() throws {
        guard try !hasSchemaMigration(version: 6) else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let selectItems = try prepare("SELECT id, protectedMetadata FROM ClipboardItems")
            defer { sqlite3_finalize(selectItems) }
            let updateItem = try prepare(
                "UPDATE ClipboardItems SET protectedMetadata = ? WHERE id = ?"
            )
            defer { sqlite3_finalize(updateItem) }
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            while sqlite3_step(selectItems) == SQLITE_ROW {
                guard let id = textColumn(0, selectItems),
                      let storedMetadata = dataColumn(1, selectItems) else { continue }
                let plaintext: Data
                if (try? decoder.decode(ClipboardPrivateMetadataV2.self, from: storedMetadata)) != nil {
                    plaintext = storedMetadata
                } else {
                    plaintext = try encryptionService().decrypt(storedMetadata)
                }
                let metadata: ClipboardPrivateMetadataV2
                if let decoded = try? decoder.decode(ClipboardPrivateMetadataV2.self, from: plaintext) {
                    metadata = decoded
                } else {
                    metadata = ClipboardPrivateMetadataV2(
                        protectedMetadata: try decoder.decode(
                            ClipboardProtectedMetadata.self,
                            from: plaintext
                        ),
                        fileURLs: [],
                        fileBookmarks: []
                    )
                }
                _ = sqlite3_reset(updateItem)
                _ = sqlite3_clear_bindings(updateItem)
                try bind(try encoder.encode(metadata), at: 1, to: updateItem)
                try bind(id, at: 2, to: updateItem)
                guard sqlite3_step(updateItem) == SQLITE_DONE else {
                    throw DatabaseError.executionFailed(databaseMessage())
                }
            }
            let selectCollections = try prepare(
                "SELECT id, protectedName FROM ClipboardCollections"
            )
            defer { sqlite3_finalize(selectCollections) }
            let updateCollection = try prepare(
                "UPDATE ClipboardCollections SET protectedName = ? WHERE id = ?"
            )
            defer { sqlite3_finalize(updateCollection) }
            while sqlite3_step(selectCollections) == SQLITE_ROW {
                guard let id = textColumn(0, selectCollections),
                      let storedName = dataColumn(1, selectCollections) else { continue }
                let plaintext = try encryptionService().decrypt(storedName)
                guard String(data: plaintext, encoding: .utf8) != nil else {
                    throw DatabaseError.executionFailed("collection name encoding is invalid")
                }
                _ = sqlite3_reset(updateCollection)
                _ = sqlite3_clear_bindings(updateCollection)
                try bind(plaintext, at: 1, to: updateCollection)
                try bind(id, at: 2, to: updateCollection)
                guard sqlite3_step(updateCollection) == SQLITE_DONE else {
                    throw DatabaseError.executionFailed(databaseMessage())
                }
            }
            try execute("""
                INSERT INTO SchemaMigrations(version, appliedAt)
                VALUES (6, strftime('%s','now'))
                """)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func hasSchemaMigration(version: Int) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM SchemaMigrations WHERE version = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        bind(version, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func migrateLegacyJSONIfNeeded() throws {
        guard fileManager.fileExists(atPath: historyFile.path),
              try settingValue(for: "jsonMigrationCompleted") != "1" else { return }

        let backup = backupsDirectory.appending(
            path: "history-before-sqlite-\(UUID().uuidString.lowercased()).json",
            directoryHint: .notDirectory
        )
        try fileManager.copyItem(at: historyFile, to: backup)
        let data = try Data(contentsOf: historyFile)
        let legacyItems = try JSONDecoder().decode([ClipboardItem].self, from: data)

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for item in legacyItems {
                try insertOrReplace(item)
            }
            try migrationFailureInjector?()
            try setSettingValue("1", for: "jsonMigrationCompleted")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }

        let migrated = backupsDirectory.appending(
            path: "history-migrated-\(UUID().uuidString.lowercased()).json",
            directoryHint: .notDirectory
        )
        try fileManager.moveItem(at: historyFile, to: migrated)
        AppLog.storage.notice("Legacy JSON migration completed; schema=\(Self.schemaVersion)")
    }

    func preserveFailedLegacyMigration() throws {
        guard fileManager.fileExists(atPath: historyFile.path) else { return }
        let failed = backupsDirectory.appending(
            path: "history-migration-failed-\(UUID().uuidString.lowercased()).json",
            directoryHint: .notDirectory
        )
        try fileManager.moveItem(at: historyFile, to: failed)
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try setSettingValue("failed", for: "jsonMigrationStatus")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

}
