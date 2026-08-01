import Foundation
import SQLite3

extension StorageService {
    func insertOrReplace(_ item: ClipboardItem) throws {
        let statement = try prepareItemUpsertStatement()
        defer { sqlite3_finalize(statement) }
        try insertOrReplace(item, using: statement, encoder: JSONEncoder())
    }

    func prepareItemUpsertStatement() throws -> OpaquePointer {
        try prepare("""
            INSERT OR REPLACE INTO ClipboardItems (
                id, type, textContent, imageFilename, thumbnailFilename, contentHash,
                createdAt, lastUsedAt, pinnedAt, isPinned, useCount, contentSubtype,
                expiresAt, isSensitive, sourceApplicationBundleID, storageVersion,
                displayTitle, payloadFilename, assetFilenames, fileURLs, fileBookmarks,
                imageWidth, imageHeight, pageCount, fileSize, isEncrypted,
                protectedMetadata, collectionID, isSnippet, pasteboardTypes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
    }

    func insertOrReplace(
        _ item: ClipboardItem,
        using statement: OpaquePointer,
        encoder: JSONEncoder
    ) throws {
        _ = sqlite3_reset(statement)
        _ = sqlite3_clear_bindings(statement)
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
        sqlite3_bind_null(statement, 17)
        try bind(item.payloadFilename, at: 18, to: statement)
        try bindEncodedCollection(item.assetFilenames, at: 19, to: statement, encoder: encoder)
        try bindEncodedCollection(item.fileURLs, at: 20, to: statement, encoder: encoder)
        try bindEncodedCollection(item.fileBookmarks, at: 21, to: statement, encoder: encoder)
        bind(item.imageWidth, at: 22, to: statement)
        bind(item.imageHeight, at: 23, to: statement)
        bind(item.pageCount, at: 24, to: statement)
        bind(item.fileSize, at: 25, to: statement)
        sqlite3_bind_int(statement, 26, item.isEncrypted ? 1 : 0)
        var metadata = item.protectedMetadata
        metadata.displayTitle = item.displayTitle
        if metadata == ClipboardProtectedMetadata() {
            sqlite3_bind_null(statement, 27)
        } else {
            let protectedMetadata = try encryptionService().encrypt(try encoder.encode(metadata))
            try bind(protectedMetadata, at: 27, to: statement)
        }
        try bind(item.collectionID?.uuidString, at: 28, to: statement)
        sqlite3_bind_int(statement, 29, item.isSnippet ? 1 : 0)
        try bindEncodedCollection(item.pasteboardTypes, at: 30, to: statement, encoder: encoder)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    func fetchAllItems() throws -> [ClipboardItem] {
        let statement = try prepare("""
            SELECT id, type, textContent, imageFilename, thumbnailFilename, contentHash,
                   createdAt, lastUsedAt, pinnedAt, isPinned, useCount, contentSubtype,
                   expiresAt, isSensitive, sourceApplicationBundleID, storageVersion,
                   displayTitle, payloadFilename, assetFilenames, fileURLs, fileBookmarks,
                   imageWidth, imageHeight, pageCount, fileSize, isEncrypted,
                   protectedMetadata, collectionID, isSnippet, pasteboardTypes
            FROM ClipboardItems
            ORDER BY createdAt DESC
            """)
        defer { sqlite3_finalize(statement) }
        var items: [ClipboardItem] = []
        let decoder = JSONDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = textColumn(0, statement),
                  let id = UUID(uuidString: idString),
                  let typeRaw = textColumn(1, statement),
                  let type = ClipboardItemType(rawValue: typeRaw),
                  let hash = textColumn(5, statement) else { continue }

            let isEncrypted = sqlite3_column_int(statement, 25) != 0
            let protectedMetadata: ClipboardProtectedMetadata
            if let encryptedMetadata = dataColumn(26, statement) {
                let metadataData = try encryptionService().decrypt(encryptedMetadata)
                protectedMetadata = try decoder.decode(
                    ClipboardProtectedMetadata.self,
                    from: metadataData
                )
            } else {
                protectedMetadata = ClipboardProtectedMetadata(
                    displayTitle: textColumn(16, statement)
                )
            }
            var text: String?
            if var textData = dataColumn(2, statement) {
                if isEncrypted {
                    textData = try encryptionService().decrypt(textData)
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
                    displayTitle: protectedMetadata.displayTitle,
                    thumbnailFilename: textColumn(4, statement),
                    contentSubtype: ClipboardContentSubtype(
                        rawValue: textColumn(11, statement) ?? ""
                    ) ?? .unknown,
                    expiresAt: dateColumn(12, statement),
                    isSensitive: sqlite3_column_int(statement, 13) != 0,
                    sourceApplicationBundleID: textColumn(14, statement),
                    storageVersion: Int(sqlite3_column_int64(statement, 15)),
                    payloadFilename: textColumn(17, statement),
                    assetFilenames: decodeArray(
                        [String].self,
                        from: dataColumn(18, statement),
                        using: decoder
                    ) ?? [],
                    fileURLs: decodeArray(
                        [String].self,
                        from: dataColumn(19, statement),
                        using: decoder
                    ) ?? [],
                    fileBookmarks: decodeArray(
                        [Data].self,
                        from: dataColumn(20, statement),
                        using: decoder
                    ) ?? [],
                    imageWidth: optionalIntColumn(21, statement),
                    imageHeight: optionalIntColumn(22, statement),
                    pageCount: optionalIntColumn(23, statement),
                    fileSize: optionalInt64Column(24, statement),
                    isEncrypted: isEncrypted,
                    protectedMetadata: protectedMetadata,
                    collectionID: textColumn(27, statement).flatMap(UUID.init(uuidString:)),
                    isSnippet: sqlite3_column_int(statement, 28) != 0,
                    pasteboardTypes: decodeArray(
                        [String].self,
                        from: dataColumn(29, statement),
                        using: decoder
                    ) ?? []
                )
            )
        }
        return items
    }

    func deleteItemRecord(id: UUID) throws {
        let statement = try prepare("DELETE FROM ClipboardItems WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    func reconcileIncompleteRecords(_ items: [ClipboardItem]) throws -> [ClipboardItem] {
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

    func databaseIntegrityIsValid() throws -> Bool {
        if let databaseIntegrityCheckOverride {
            return try databaseIntegrityCheckOverride()
        }
        let statement = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return textColumn(0, statement) == "ok"
    }

    func attemptDatabaseRecovery() throws {
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

    var isCorruptionState: Bool {
        if let databaseCorruptionStateOverride { return databaseCorruptionStateOverride }
        guard let database else { return false }
        let code = sqlite3_errcode(database)
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }

    func settingValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM Settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return textColumn(0, statement)
    }

    func setSettingValue(_ value: String, for key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO Settings(key, value) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, to: statement)
        try bind(value, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        try operationFailureInjector?(.prepareSQL(sql))
        guard let database else { throw DatabaseError.openFailed("missing handle") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.preparationFailed(databaseMessage())
        }
        return statement
    }

    func execute(_ sql: String) throws {
        try operationFailureInjector?(.executeSQL(sql))
        guard let database else { throw DatabaseError.openFailed("missing handle") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? databaseMessage()
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }

    func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        guard sqliteTextBinder(statement, index, value) == SQLITE_OK else {
            throw DatabaseError.bindingFailed
        }
    }

    func bind(_ data: Data, at index: Int32, to statement: OpaquePointer) throws {
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        guard result == SQLITE_OK else { throw DatabaseError.bindingFailed }
    }

    func bindEncodedCollection<T: Collection & Encodable>(
        _ value: T,
        at index: Int32,
        to statement: OpaquePointer,
        encoder: JSONEncoder
    ) throws {
        if value.isEmpty {
            sqlite3_bind_null(statement, index)
        } else {
            try bind(try encoder.encode(value), at: index, to: statement)
        }
    }

    func bind(_ date: Date?, at index: Int32, to statement: OpaquePointer) {
        if let date {
            sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ value: Int?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func textColumn(_ index: Int32, _ statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    func dataColumn(_ index: Int32, _ statement: OpaquePointer) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    func dateColumn(_ index: Int32, _ statement: OpaquePointer) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    func optionalIntColumn(_ index: Int32, _ statement: OpaquePointer) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    func optionalInt64Column(_ index: Int32, _ statement: OpaquePointer) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int64(sqlite3_column_int64(statement, index))
    }

    func decodeArray<T: Decodable>(
        _ type: T.Type,
        from data: Data?,
        using decoder: JSONDecoder
    ) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func databaseMessage() -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }
}

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
