import Foundation
import SQLite3

actor StorageService {
    static let maximumHistoryCount = 100
    static let schemaVersion = 3

    nonisolated let baseDirectory: URL
    nonisolated let imagesDirectory: URL
    nonisolated let thumbnailsDirectory: URL
    nonisolated let payloadsDirectory: URL
    nonisolated let backupsDirectory: URL
    nonisolated let stagingDirectory: URL
    nonisolated let historyFile: URL
    nonisolated let databaseFile: URL

    let fileManager: FileManager
    let migrationFailureInjector: (@Sendable () throws -> Void)?
    let operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)?
    var encryption: EncryptionService?
    let keyProvider: (any MasterKeyProvider)?
    nonisolated(unsafe) var database: OpaquePointer?
    var isInitialized = false
    var isClosed = false

    init(
        baseDirectory: URL = StorageService.defaultBaseDirectory(),
        fileManager: FileManager = .default,
        encryptionService: EncryptionService? = nil,
        keyProvider: (any MasterKeyProvider)? = nil,
        migrationFailureInjector: (@Sendable () throws -> Void)? = nil,
        operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)? = nil
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
        self.operationFailureInjector = operationFailureInjector
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
        let items = try fetchAllItems()
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
                  let encryptedName = dataColumn(1, statement) else { continue }
            let nameData = try encryptionService().decrypt(encryptedName)
            guard let name = String(data: nameData, encoding: .utf8) else {
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
        let protectedName = try encryptionService().encrypt(Data(name.utf8))
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

    func verifyEncryptionAvailable() throws {
        try ensureInitialized()
        _ = try encryptionService()
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
            try upsertThrowing(item)
        } catch {
            AppLog.storage.error(
                "Item upsert failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func upsertThrowing(_ item: ClipboardItem) throws {
        guard !item.isSensitive || item.isEncrypted else {
            throw DatabaseError.executionFailed("sensitive item is not encrypted")
        }
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
        guard items.allSatisfy({ !$0.isSensitive || $0.isEncrypted }) else {
            throw DatabaseError.executionFailed("sensitive batch item is not encrypted")
        }
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for item in items {
                try insertOrReplace(item)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func importBatchThrowing(
        items: [ClipboardItem],
        collections: [ClipboardCollection]
    ) throws {
        guard items.allSatisfy({ !$0.isSensitive || $0.isEncrypted }) else {
            throw DatabaseError.executionFailed("sensitive batch item is not encrypted")
        }
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for collection in collections {
                try insertOrReplaceCollection(collection)
            }
            for item in items {
                try insertOrReplace(item)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteBatchThrowing(ids: [UUID]) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for id in ids {
                try deleteItemRecord(id: id)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
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

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    nonisolated static func defaultBaseDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return applicationSupport.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
    }
}
