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
            try execute("CREATE INDEX IF NOT EXISTS idx_items_text ON ClipboardItems(textContent)")
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
