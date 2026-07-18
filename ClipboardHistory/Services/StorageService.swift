import Foundation
import SQLite3

actor StorageService {
    static let maximumHistoryCount = 100
    static let schemaVersion = 1

    nonisolated let baseDirectory: URL
    nonisolated let imagesDirectory: URL
    nonisolated let thumbnailsDirectory: URL
    nonisolated let payloadsDirectory: URL
    nonisolated let backupsDirectory: URL
    nonisolated let stagingDirectory: URL
    nonisolated let historyFile: URL
    nonisolated let databaseFile: URL

    private let fileManager: FileManager
    private let migrationFailureInjector: (@Sendable () throws -> Void)?
    private var encryption: EncryptionService?
    private let usesLiveKeychain: Bool
    private nonisolated(unsafe) var database: OpaquePointer?
    private var isInitialized = false
    private var isClosed = false

    init(
        baseDirectory: URL = StorageService.defaultBaseDirectory(),
        fileManager: FileManager = .default,
        encryptionService: EncryptionService? = nil,
        migrationFailureInjector: (@Sendable () throws -> Void)? = nil
    ) {
        self.baseDirectory = baseDirectory
        imagesDirectory = baseDirectory.appending(path: "Images", directoryHint: .isDirectory)
        thumbnailsDirectory = baseDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        payloadsDirectory = baseDirectory.appending(path: "Payloads", directoryHint: .isDirectory)
        backupsDirectory = baseDirectory.appending(path: "Backups", directoryHint: .isDirectory)
        stagingDirectory = baseDirectory.appending(path: ".staging", directoryHint: .isDirectory)
        historyFile = baseDirectory.appending(path: "history.json", directoryHint: .notDirectory)
        databaseFile = baseDirectory.appending(path: "history.sqlite3", directoryHint: .notDirectory)
        self.fileManager = fileManager
        self.migrationFailureInjector = migrationFailureInjector
        if let encryptionService {
            encryption = encryptionService
            usesLiveKeychain = false
        } else if baseDirectory.standardizedFileURL == Self.defaultBaseDirectory().standardizedFileURL {
            encryption = nil
            usesLiveKeychain = true
        } else {
            encryption = EncryptionService.ephemeral()
            usesLiveKeychain = false
        }
    }

    func loadHistory() -> [ClipboardItem] {
        do {
            try ensureInitialized()
            let items = try fetchAllItems()
            let validItems = try reconcileIncompleteRecords(items)
            try cleanupOrphanedFiles(referencedBy: validItems)
            return validItems
        } catch {
            AppLog.storage.error(
                "History database load failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return []
        }
    }

    func saveHistory(_ items: [ClipboardItem]) {
        do {
            try ensureInitialized()
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM ClipboardItems")
                for item in items where !item.isSensitive || item.isEncrypted {
                    try insertOrReplace(item)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch {
            AppLog.storage.error(
                "History save failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func upsert(_ item: ClipboardItem) {
        guard !item.isSensitive || item.isEncrypted else { return }
        do {
            try ensureInitialized()
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try insertOrReplace(item)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch {
            AppLog.storage.error(
                "Item upsert failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        do {
            try ensureInitialized()
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try deleteItemRecord(id: item.id)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
            deleteAssociatedFiles(for: item)
        } catch {
            AppLog.storage.error(
                "Item deletion failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func storeImage(_ pngData: Data, id: UUID, encrypt: Bool = false, index: Int? = nil) -> String? {
        let suffix = index.map { "-\($0)" } ?? ""
        let filename = "\(id.uuidString.lowercased())\(suffix).png"
        return storeFile(
            data: pngData,
            logicalFilename: filename,
            directory: imagesDirectory,
            encrypt: encrypt
        ) ? filename : nil
    }

    func storePayload(
        _ data: Data,
        id: UUID,
        extension fileExtension: String,
        encrypt: Bool
    ) -> String? {
        let filename = "\(id.uuidString.lowercased()).\(fileExtension)"
        return storeFile(
            data: data,
            logicalFilename: filename,
            directory: payloadsDirectory,
            encrypt: encrypt
        ) ? filename : nil
    }

    func storeThumbnail(_ data: Data, filename: String, encrypt: Bool) -> Bool {
        storeFile(
            data: data,
            logicalFilename: filename,
            directory: thumbnailsDirectory,
            encrypt: encrypt
        )
    }

    func imageData(filename: String, isEncrypted: Bool = false) -> Data? {
        loadFile(filename: filename, directory: imagesDirectory, isEncrypted: isEncrypted)
    }

    func payloadData(filename: String, isEncrypted: Bool) -> Data? {
        loadFile(filename: filename, directory: payloadsDirectory, isEncrypted: isEncrypted)
    }

    func thumbnailData(filename: String, isEncrypted: Bool) -> Data? {
        loadFile(filename: filename, directory: thumbnailsDirectory, isEncrypted: isEncrypted)
    }

    func deleteImages(for items: [ClipboardItem]) {
        for item in items {
            deleteAssociatedFiles(for: item)
        }
    }

    func clearAll() {
        do {
            try ensureInitialized()
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM ClipboardItems")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
            for directory in [imagesDirectory, thumbnailsDirectory, payloadsDirectory, stagingDirectory] {
                try recreateDirectory(directory)
            }
            try rotateEncryptionKeyAfterCompleteErasure()
        } catch {
            AppLog.storage.error(
                "History clear failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

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
                return "SQLite schema \(Self.schemaVersion); legacy migration preserved after failure"
            }
            return try settingValue(for: "jsonMigrationCompleted") == "1"
                ? "SQLite schema \(Self.schemaVersion); JSON migration complete"
                : "SQLite schema \(Self.schemaVersion); no legacy migration"
        } catch {
            return "Database unavailable"
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

    nonisolated func imageURL(filename: String, isEncrypted: Bool = false) -> URL {
        physicalURL(filename: filename, directory: imagesDirectory, encrypted: isEncrypted)
    }

    nonisolated func payloadURL(filename: String, isEncrypted: Bool = false) -> URL {
        physicalURL(filename: filename, directory: payloadsDirectory, encrypted: isEncrypted)
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    private func ensureInitialized() throws {
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

    private func openDatabase() throws {
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

    private func createSchemaIfNeeded() throws {
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
    }

    private func migrateLegacyJSONIfNeeded() throws {
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

    private func preserveFailedLegacyMigration() throws {
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

    private func insertOrReplace(_ item: ClipboardItem) throws {
        let sql = """
            INSERT OR REPLACE INTO ClipboardItems (
                id, type, textContent, imageFilename, thumbnailFilename, contentHash,
                createdAt, lastUsedAt, pinnedAt, isPinned, useCount, contentSubtype,
                expiresAt, isSensitive, sourceApplicationBundleID, storageVersion,
                displayTitle, payloadFilename, assetFilenames, fileURLs, fileBookmarks,
                imageWidth, imageHeight, pageCount, fileSize, isEncrypted
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, at: 1, to: statement)
        try bind(item.type.rawValue, at: 2, to: statement)
        if let text = item.text {
            var textData = Data(text.utf8)
            if item.isEncrypted {
                textData = try encryptionService().encrypt(textData)
            }
            try bind(textData, at: 3, to: statement)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        try bind(item.imageFilename, at: 4, to: statement)
        try bind(item.thumbnailFilename, at: 5, to: statement)
        try bind(item.hash, at: 6, to: statement)
        sqlite3_bind_double(statement, 7, item.creationDate.timeIntervalSince1970)
        bind(item.lastUsedAt, at: 8, to: statement)
        bind(item.pinnedAt, at: 9, to: statement)
        sqlite3_bind_int(statement, 10, item.isPinned ? 1 : 0)
        sqlite3_bind_int64(statement, 11, sqlite3_int64(item.useCount))
        try bind(item.contentSubtype.rawValue, at: 12, to: statement)
        bind(item.expiresAt, at: 13, to: statement)
        sqlite3_bind_int(statement, 14, item.isSensitive ? 1 : 0)
        try bind(item.sourceApplicationBundleID, at: 15, to: statement)
        sqlite3_bind_int64(statement, 16, sqlite3_int64(item.storageVersion))
        try bind(item.displayTitle, at: 17, to: statement)
        try bind(item.payloadFilename, at: 18, to: statement)
        try bind(try JSONEncoder().encode(item.assetFilenames), at: 19, to: statement)
        try bind(try JSONEncoder().encode(item.fileURLs), at: 20, to: statement)
        try bind(try JSONEncoder().encode(item.fileBookmarks), at: 21, to: statement)
        bind(item.imageWidth, at: 22, to: statement)
        bind(item.imageHeight, at: 23, to: statement)
        bind(item.pageCount, at: 24, to: statement)
        bind(item.fileSize, at: 25, to: statement)
        sqlite3_bind_int(statement, 26, item.isEncrypted ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    private func fetchAllItems() throws -> [ClipboardItem] {
        let statement = try prepare("""
            SELECT id, type, textContent, imageFilename, thumbnailFilename, contentHash,
                   createdAt, lastUsedAt, pinnedAt, isPinned, useCount, contentSubtype,
                   expiresAt, isSensitive, sourceApplicationBundleID, storageVersion,
                   displayTitle, payloadFilename, assetFilenames, fileURLs, fileBookmarks,
                   imageWidth, imageHeight, pageCount, fileSize, isEncrypted
            FROM ClipboardItems
            ORDER BY createdAt DESC
            """)
        defer { sqlite3_finalize(statement) }
        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = textColumn(0, statement),
                  let id = UUID(uuidString: idString),
                  let typeRaw = textColumn(1, statement),
                  let type = ClipboardItemType(rawValue: typeRaw),
                  let hash = textColumn(5, statement) else { continue }

            let isEncrypted = sqlite3_column_int(statement, 25) != 0
            var text: String?
            if var textData = dataColumn(2, statement) {
                if isEncrypted {
                    textData = (try? encryptionService().decrypt(textData)) ?? Data()
                }
                text = String(data: textData, encoding: .utf8)
            }

            items.append(
                ClipboardItem(
                    id: id,
                    type: type,
                    text: text,
                    imageFilename: textColumn(3, statement),
                    creationDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    hash: hash,
                    isPinned: sqlite3_column_int(statement, 9) != 0,
                    pinnedAt: dateColumn(8, statement),
                    lastUsedAt: dateColumn(7, statement),
                    useCount: Int(sqlite3_column_int64(statement, 10)),
                    displayTitle: textColumn(16, statement),
                    thumbnailFilename: textColumn(4, statement),
                    contentSubtype: ClipboardContentSubtype(
                        rawValue: textColumn(11, statement) ?? ""
                    ) ?? .unknown,
                    expiresAt: dateColumn(12, statement),
                    isSensitive: sqlite3_column_int(statement, 13) != 0,
                    sourceApplicationBundleID: textColumn(14, statement),
                    storageVersion: Int(sqlite3_column_int64(statement, 15)),
                    payloadFilename: textColumn(17, statement),
                    assetFilenames: decodeArray([String].self, from: dataColumn(18, statement)) ?? [],
                    fileURLs: decodeArray([String].self, from: dataColumn(19, statement)) ?? [],
                    fileBookmarks: decodeArray([Data].self, from: dataColumn(20, statement)) ?? [],
                    imageWidth: optionalIntColumn(21, statement),
                    imageHeight: optionalIntColumn(22, statement),
                    pageCount: optionalIntColumn(23, statement),
                    fileSize: optionalInt64Column(24, statement),
                    isEncrypted: isEncrypted
                )
            )
        }
        return items
    }

    private func deleteItemRecord(id: UUID) throws {
        let statement = try prepare("DELETE FROM ClipboardItems WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    private func reconcileIncompleteRecords(_ items: [ClipboardItem]) throws -> [ClipboardItem] {
        var validItems: [ClipboardItem] = []
        for var item in items where item.isStructurallyValid {
            var shouldKeep = true
            switch item.type {
            case .image:
                shouldKeep = item.imageFilename.map {
                    fileExists(logicalFilename: $0, directory: imagesDirectory, encrypted: item.isEncrypted)
                } ?? false
            case .imageGroup:
                let existing = item.assetFilenames.filter {
                    fileExists(logicalFilename: $0, directory: imagesDirectory, encrypted: item.isEncrypted)
                }
                shouldKeep = !existing.isEmpty
                if shouldKeep, existing != item.assetFilenames {
                    item.assetFilenames = existing
                    try insertOrReplace(item)
                    AppLog.storage.notice("Incomplete image group recovered; remaining=\(existing.count)")
                }
            case .pdf:
                shouldKeep = item.payloadFilename.map {
                    fileExists(logicalFilename: $0, directory: payloadsDirectory, encrypted: item.isEncrypted)
                } ?? false
            case .text, .richText, .files:
                break
            }
            if shouldKeep {
                validItems.append(item)
            } else {
                try deleteItemRecord(id: item.id)
                deleteAssociatedFiles(for: item)
                AppLog.storage.notice("Orphaned database record removed; type=\(item.type.rawValue)")
            }
        }
        for invalid in items where !invalid.isStructurallyValid {
            try deleteItemRecord(id: invalid.id)
            deleteAssociatedFiles(for: invalid)
        }
        return validItems
    }

    private func databaseIntegrityIsValid() throws -> Bool {
        let statement = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return textColumn(0, statement) == "ok"
    }

    private func attemptDatabaseRecovery() throws {
        try? execute("REINDEX")
        try? execute("VACUUM")
        if (try? databaseIntegrityIsValid()) == true { return }

        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        let corruptBackup = backupsDirectory.appending(
            path: "history-corrupt-\(UUID().uuidString.lowercased()).sqlite3",
            directoryHint: .notDirectory
        )
        if fileManager.fileExists(atPath: databaseFile.path) {
            try fileManager.moveItem(at: databaseFile, to: corruptBackup)
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseFile.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.moveItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: corruptBackup.path + suffix)
                )
            }
        }
        AppLog.storage.fault("Database corruption preserved; recovery=new-database")
        try openDatabase()
        try createSchemaIfNeeded()
    }

    private var isCorruptionState: Bool {
        guard let database else { return false }
        let code = sqlite3_errcode(database)
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }

    private func settingValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM Settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return textColumn(0, statement)
    }

    private func setSettingValue(_ value: String, for key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO Settings(key, value) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        try bind(value, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw DatabaseError.openFailed("missing handle") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.preparationFailed(databaseMessage())
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw DatabaseError.openFailed("missing handle") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? databaseMessage()
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw DatabaseError.bindingFailed
        }
    }

    private func bind(_ data: Data, at index: Int32, to statement: OpaquePointer) throws {
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        guard result == SQLITE_OK else { throw DatabaseError.bindingFailed }
    }

    private func bind(_ date: Date?, at index: Int32, to statement: OpaquePointer) {
        if let date {
            sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Int?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func textColumn(_ index: Int32, _ statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func dataColumn(_ index: Int32, _ statement: OpaquePointer) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func dateColumn(_ index: Int32, _ statement: OpaquePointer) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func optionalIntColumn(_ index: Int32, _ statement: OpaquePointer) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func optionalInt64Column(_ index: Int32, _ statement: OpaquePointer) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int64(sqlite3_column_int64(statement, index))
    }

    private func decodeArray<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func databaseMessage() -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }

    private func storeFile(
        data: Data,
        logicalFilename: String,
        directory: URL,
        encrypt: Bool
    ) -> Bool {
        do {
            try createDirectoriesIfNeeded()
            let storedData: Data
            if encrypt {
                storedData = try encryptionService().encrypt(data)
            } else {
                storedData = data
            }
            let destination = physicalURL(
                filename: logicalFilename,
                directory: directory,
                encrypted: encrypt
            )
            let staged = stagingDirectory.appending(
                path: "\(UUID().uuidString.lowercased()).tmp",
                directoryHint: .notDirectory
            )
            try storedData.write(to: staged, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
            return true
        } catch {
            AppLog.storage.error(
                "Asset store failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    private func loadFile(filename: String, directory: URL, isEncrypted: Bool) -> Data? {
        let primary = physicalURL(filename: filename, directory: directory, encrypted: isEncrypted)
        let legacy = physicalURL(filename: filename, directory: directory, encrypted: false)
        let source = fileManager.fileExists(atPath: primary.path) ? primary : legacy
        do {
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            if isEncrypted, source == primary {
                return try encryptionService().decrypt(data)
            }
            return data
        } catch {
            AppLog.storage.error(
                "Asset read failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    private nonisolated func physicalURL(filename: String, directory: URL, encrypted: Bool) -> URL {
        directory.appending(
            path: encrypted ? "\(filename).enc" : filename,
            directoryHint: .notDirectory
        )
    }

    private func deleteAssociatedFiles(for item: ClipboardItem) {
        var imageNames = item.assetFilenames
        if let imageFilename = item.imageFilename {
            imageNames.append(imageFilename)
        }
        for filename in imageNames {
            deleteLogicalFile(filename, from: imagesDirectory)
        }
        if let thumbnailFilename = item.thumbnailFilename {
            deleteLogicalFile(thumbnailFilename, from: thumbnailsDirectory)
        }
        if let payloadFilename = item.payloadFilename {
            deleteLogicalFile(payloadFilename, from: payloadsDirectory)
        }
    }

    private func rewriteAssets(for item: ClipboardItem, encrypt: Bool) throws -> Bool {
        var imageNames = item.assetFilenames
        if let filename = item.imageFilename { imageNames.append(filename) }
        for filename in imageNames {
            guard let data = loadFile(
                filename: filename,
                directory: imagesDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: imagesDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        if let filename = item.thumbnailFilename,
           fileExists(logicalFilename: filename, directory: thumbnailsDirectory, encrypted: item.isEncrypted) {
            guard let data = loadFile(
                filename: filename,
                directory: thumbnailsDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: thumbnailsDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        if let filename = item.payloadFilename {
            guard let data = loadFile(
                filename: filename,
                directory: payloadsDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: payloadsDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        return true
    }

    private func deletePhysicalAssets(for item: ClipboardItem, encrypted: Bool) {
        var imageNames = item.assetFilenames
        if let filename = item.imageFilename { imageNames.append(filename) }
        for filename in imageNames {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: imagesDirectory, encrypted: encrypted)
            )
        }
        if let filename = item.thumbnailFilename {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: thumbnailsDirectory, encrypted: encrypted)
            )
        }
        if let filename = item.payloadFilename {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: payloadsDirectory, encrypted: encrypted)
            )
        }
    }

    private func fileExists(logicalFilename: String, directory: URL, encrypted: Bool) -> Bool {
        fileManager.fileExists(
            atPath: physicalURL(filename: logicalFilename, directory: directory, encrypted: encrypted).path
        )
    }

    private func rotateEncryptionKeyAfterCompleteErasure() throws {
        if usesLiveKeychain {
            _ = try KeychainService.loadOrCreateKey()
            let keyData = try KeychainService.generateRandomKey()
            try KeychainService.rotateKey(with: keyData)
            encryption = try EncryptionService(keyData: keyData)
        } else if encryption != nil {
            encryption = .ephemeral()
        } else {
            return
        }
        AppLog.storage.notice("Encryption key rotated after complete history erasure")
    }

    private func encryptionService() throws -> EncryptionService {
        if let encryption { return encryption }
        guard usesLiveKeychain else { throw DatabaseError.encryptionUnavailable }
        let liveEncryption = try EncryptionService.live()
        encryption = liveEncryption
        return liveEncryption
    }

    private func deleteLogicalFile(_ filename: String, from directory: URL) {
        for encrypted in [false, true] {
            let url = physicalURL(filename: filename, directory: directory, encrypted: encrypted)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func associatedFileSize(for item: ClipboardItem) -> Int64 {
        var total: Int64 = 0
        var imageNames = item.assetFilenames
        if let imageFilename = item.imageFilename { imageNames.append(imageFilename) }
        for filename in imageNames {
            total += logicalFileSize(filename, directory: imagesDirectory)
        }
        if let filename = item.thumbnailFilename {
            total += logicalFileSize(filename, directory: thumbnailsDirectory)
        }
        if let filename = item.payloadFilename {
            total += logicalFileSize(filename, directory: payloadsDirectory)
        }
        return total
    }

    private func logicalFileSize(_ filename: String, directory: URL) -> Int64 {
        max(
            fileSize(at: physicalURL(filename: filename, directory: directory, encrypted: false)),
            fileSize(at: physicalURL(filename: filename, directory: directory, encrypted: true))
        )
    }

    private func cleanupOrphanedFiles(referencedBy items: [ClipboardItem]) throws {
        var imageNames = Set(items.flatMap(\.assetFilenames))
        imageNames.formUnion(items.compactMap(\.imageFilename))
        let thumbnailNames = Set(items.compactMap(\.thumbnailFilename))
        let payloadNames = Set(items.compactMap(\.payloadFilename))
        try removeOrphans(in: imagesDirectory, logicalNames: imageNames)
        try removeOrphans(in: thumbnailsDirectory, logicalNames: thumbnailNames)
        try removeOrphans(in: payloadsDirectory, logicalNames: payloadNames)
    }

    private func removeOrphans(in directory: URL, logicalNames: Set<String>) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let logicalName = url.lastPathComponent.hasSuffix(".enc")
                ? String(url.lastPathComponent.dropLast(4))
                : url.lastPathComponent
            if !logicalNames.contains(logicalName) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func createDirectoriesIfNeeded() throws {
        for directory in [
            imagesDirectory, thumbnailsDirectory, payloadsDirectory,
            backupsDirectory, stagingDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func cleanupAbandonedStagingFiles() throws {
        let files = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func recreateDirectory(_ directory: URL) throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(at: file)
        }
        return total
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private nonisolated static func defaultBaseDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return applicationSupport.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
