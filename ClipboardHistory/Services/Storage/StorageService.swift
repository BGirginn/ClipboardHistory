import Foundation
import SQLite3

actor StorageService {
    typealias SQLiteTextBinder = @Sendable (OpaquePointer, Int32, String) -> Int32

    static let maximumHistoryCount = 100
    static let schemaVersion = 6

    nonisolated let baseDirectory: URL
    nonisolated let imagesDirectory: URL
    nonisolated let thumbnailsDirectory: URL
    nonisolated let payloadsDirectory: URL
    nonisolated let backupsDirectory: URL
    nonisolated let stagingDirectory: URL
    nonisolated let operationsDirectory: URL
    nonisolated let historyFile: URL
    nonisolated let databaseFile: URL

    let fileManager: FileManager
    let migrationFailureInjector: (@Sendable () throws -> Void)?
    let operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)?
    let databaseIntegrityCheckOverride: (@Sendable () throws -> Bool)?
    let databaseCorruptionStateOverride: Bool?
    let sqliteTextBinder: SQLiteTextBinder
    var encryption: EncryptionService?
    let keyProvider: (any MasterKeyProvider)?
    var noteEncryption: EncryptionService?
    let noteKeyProvider: (any MasterKeyProvider)?
    nonisolated(unsafe) var database: OpaquePointer?
    var isInitialized = false
    var isClosed = false

    init(
        baseDirectory: URL = StorageService.defaultBaseDirectory(),
        fileManager: FileManager = .default,
        encryptionService: EncryptionService? = nil,
        keyProvider: (any MasterKeyProvider)? = nil,
        noteEncryptionService: EncryptionService? = nil,
        noteKeyProvider: (any MasterKeyProvider)? = nil,
        migrationFailureInjector: (@Sendable () throws -> Void)? = nil,
        operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)? = nil,
        databaseIntegrityCheckOverride: (@Sendable () throws -> Bool)? = nil,
        databaseCorruptionStateOverride: Bool? = nil,
        sqliteTextBinder: @escaping SQLiteTextBinder = { statement, index, value in
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        }
    ) {
        self.baseDirectory = baseDirectory
        imagesDirectory = baseDirectory.appending(path: "Images", directoryHint: .isDirectory)
        thumbnailsDirectory = baseDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        payloadsDirectory = baseDirectory.appending(path: "Payloads", directoryHint: .isDirectory)
        backupsDirectory = baseDirectory.appending(path: "Backups", directoryHint: .isDirectory)
        stagingDirectory = baseDirectory.appending(path: ".staging", directoryHint: .isDirectory)
        operationsDirectory = baseDirectory.appending(path: ".operations", directoryHint: .isDirectory)
        historyFile = baseDirectory.appending(path: "history.json", directoryHint: .notDirectory)
        databaseFile = baseDirectory.appending(path: "history.sqlite3", directoryHint: .notDirectory)
        self.fileManager = fileManager
        self.migrationFailureInjector = migrationFailureInjector
        self.operationFailureInjector = operationFailureInjector
        self.databaseIntegrityCheckOverride = databaseIntegrityCheckOverride
        self.databaseCorruptionStateOverride = databaseCorruptionStateOverride
        self.sqliteTextBinder = sqliteTextBinder
        if let encryptionService {
            encryption = encryptionService
            self.keyProvider = nil
        } else if let keyProvider {
            encryption = nil
            self.keyProvider = keyProvider
        } else if baseDirectory.standardizedFileURL == Self.defaultBaseDirectory().standardizedFileURL {
            encryption = nil
            self.keyProvider = KeychainMasterKeyProvider.active
        } else {
            encryption = EncryptionService.ephemeral()
            self.keyProvider = nil
        }
        if let noteEncryptionService {
            noteEncryption = noteEncryptionService
            self.noteKeyProvider = nil
        } else if let noteKeyProvider {
            noteEncryption = nil
            self.noteKeyProvider = noteKeyProvider
        } else if baseDirectory.standardizedFileURL == Self.defaultBaseDirectory().standardizedFileURL {
            noteEncryption = nil
            self.noteKeyProvider = KeychainMasterKeyProvider.notes
        } else {
            noteEncryption = EncryptionService.ephemeral()
            self.noteKeyProvider = nil
        }
    }

    func loadHistory() -> [ClipboardItem] {
        do {
            return try loadHistoryThrowing()
        } catch {
            AppLog.storage.error(
                "History database load failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return []
        }
    }

    func loadHistoryThrowing() throws -> [ClipboardItem] {
        try ensureInitialized()
        var items = try fetchAllItems()
        if items.contains(where: \.isEncrypted) {
            try migrateLegacyEncryptedItems(items: items)
            items = try fetchAllItems()
        }
        let validItems = try reconcileIncompleteRecords(items)
        try cleanupOrphanedFiles(referencedBy: validItems)
        return validItems
    }

    func loadCollectionsThrowing() throws -> [ClipboardCollection] {
        try ensureInitialized()
        let statement = try prepare("""
            SELECT id, protectedName, createdAt, sortOrder
            FROM ClipboardCollections
            ORDER BY sortOrder ASC, createdAt ASC
            """)
        defer { sqlite3_finalize(statement) }
        var collections: [ClipboardCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = textColumn(0, statement),
                  let id = UUID(uuidString: idText),
                  let nameData = dataColumn(1, statement),
                  let name = String(data: nameData, encoding: .utf8) else {
                throw DatabaseError.executionFailed("invalid collection name encoding")
            }
            collections.append(
                ClipboardCollection(
                    id: id,
                    name: name,
                    creationDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    sortOrder: Int(sqlite3_column_int64(statement, 3))
                )
            )
        }
        return collections
    }

    func upsertCollection(_ collection: ClipboardCollection) throws {
        try ensureInitialized()
        try insertOrReplaceCollection(collection)
    }

    func upsertCollectionsBatchThrowing(_ collections: [ClipboardCollection]) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for collection in collections {
                try insertOrReplaceCollection(collection)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func insertOrReplaceCollection(_ collection: ClipboardCollection) throws {
        let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DatabaseError.executionFailed("empty collection name") }
        let protectedName = Data(name.utf8)
        let statement = try prepare("""
            INSERT OR REPLACE INTO ClipboardCollections(id, protectedName, createdAt, sortOrder)
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bind(collection.id.uuidString, at: 1, to: statement)
        try bind(protectedName, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, collection.creationDate.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(collection.sortOrder))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    func deleteCollection(id: UUID) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let clearStatement = try prepare("UPDATE ClipboardItems SET collectionID = NULL WHERE collectionID = ?")
            try bind(id.uuidString, at: 1, to: clearStatement)
            guard sqlite3_step(clearStatement) == SQLITE_DONE else {
                sqlite3_finalize(clearStatement)
                throw DatabaseError.executionFailed(databaseMessage())
            }
            sqlite3_finalize(clearStatement)
            let deleteStatement = try prepare("DELETE FROM ClipboardCollections WHERE id = ?")
            try bind(id.uuidString, at: 1, to: deleteStatement)
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                sqlite3_finalize(deleteStatement)
                throw DatabaseError.executionFailed(databaseMessage())
            }
            sqlite3_finalize(deleteStatement)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func verifyStorageAvailable() throws {
        try ensureInitialized()
    }

    func saveHistory(_ items: [ClipboardItem]) {
        do {
            try ensureInitialized()
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM ClipboardItems")
                let statement = try prepareItemUpsertStatement()
                defer { sqlite3_finalize(statement) }
                let encoder = JSONEncoder()
                for item in items where !item.isSensitive || item.isEncrypted {
                    try insertOrReplace(item, using: statement, encoder: encoder)
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
        do {
            try upsertThrowing(item)
        } catch {
            AppLog.storage.error(
                "Item upsert failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func upsertThrowing(_ item: ClipboardItem) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try insertOrReplace(item)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func upsertBatchThrowing(_ items: [ClipboardItem]) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepareItemUpsertStatement()
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            for item in items {
                try insertOrReplace(item, using: statement, encoder: encoder)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func importBatchThrowing(
        items: [ClipboardItem],
        collections: [ClipboardCollection],
        notes: [Note] = []
    ) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for collection in collections {
                try insertOrReplaceCollection(collection)
            }
            let statement = try prepareItemUpsertStatement()
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            for item in items {
                try insertOrReplace(item, using: statement, encoder: encoder)
            }
            for note in notes {
                try insertOrReplace(note)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteBatchThrowing(items: [ClipboardItem]) throws -> StorageMutationOutcome {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for item in items {
                try deleteItemRecord(id: item.id)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }

        var cleanupFailures: [String] = []
        for item in items {
            do {
                try deleteAssociatedFilesThrowing(for: item)
            } catch {
                cleanupFailures.append(item.id.uuidString)
            }
        }
        return StorageMutationOutcome(
            persistentChangeCommitted: true,
            cleanupFailures: cleanupFailures
        )
    }

    func deleteItem(_ item: ClipboardItem) throws -> StorageMutationOutcome {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try deleteItemRecord(id: item.id)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }

        do {
            try deleteAssociatedFilesThrowing(for: item)
            return .committed
        } catch {
            AppLog.storage.error(
                "Item data was deleted but asset cleanup failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return StorageMutationOutcome(
                persistentChangeCommitted: true,
                cleanupFailures: [String(describing: type(of: error))]
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

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    nonisolated static func defaultBaseDirectory() -> URL {
        URL.applicationSupportDirectory.appending(
            path: "ClipboardHistory",
            directoryHint: .isDirectory
        )
    }
}
