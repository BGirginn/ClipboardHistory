import Foundation
import SQLite3
import XCTest

@testable import ClipboardHistory

final class ProtectedMetadataTests: XCTestCase {
    func testClipboardMetadataRoundTripsAsOpenStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryProtectedMetadata-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        let id = UUID()
        let imageFilename = "\(id.uuidString.lowercased()).png"
        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFilename: imageFilename,
            hash: "metadata-hash",
            displayTitle: "Factory alarm screenshot",
            fileURLs: ["/Users/example/Secret Project/plan.pdf"],
            fileBookmarks: [Data("private-bookmark".utf8)],
            protectedMetadata: ClipboardProtectedMetadata(
                displayTitle: "Factory alarm screenshot",
                tags: ["urgent", "night shift"],
                extractedText: "Pressure is above threshold",
                qrCodeText: "local-machine-42",
                colorHex: "#FF3300"
            ),
            collectionID: UUID(),
            isSnippet: true,
            pasteboardTypes: ["public.png"]
        )
        _ = await storage.storeImage(Data("image".utf8), id: item.id)
        await storage.upsert(item)
        await storage.close()

        let databaseData = try Data(contentsOf: storage.databaseFile)
        for value in [
            "Factory alarm screenshot", "urgent", "night shift",
            "Pressure is above threshold", "local-machine-42", "#FF3300",
            "Secret Project", "cHJpdmF0ZS1ib29rbWFyaw=="
        ] {
            XCTAssertNotNil(databaseData.range(of: Data(value.utf8)), "Missing plaintext: \(value)")
        }

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        let history = try await reopened.loadHistoryThrowing()
        let loaded = try XCTUnwrap(history.first)
        XCTAssertEqual(loaded.protectedMetadata, item.protectedMetadata)
        XCTAssertEqual(loaded.fileURLs, item.fileURLs)
        XCTAssertEqual(loaded.fileBookmarks, item.fileBookmarks)
        XCTAssertEqual(loaded.collectionID, item.collectionID)
        XCTAssertTrue(loaded.isSnippet)
        XCTAssertEqual(loaded.pasteboardTypes, ["public.png"])
    }

    func testSchemaMigrationTwoIsAtomicAndRecorded() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistorySchemaTwo-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(baseDirectory: directory)
        try await storage.verifyStorageAvailable()
        await storage.close()

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storage.databaseFile.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM SchemaMigrations WHERE version IN (1, 2, 3, 4, 5, 6)", database: openedDatabase), 6)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM pragma_table_info('ClipboardItems') WHERE name IN ('protectedMetadata', 'collectionID', 'isSnippet', 'pasteboardTypes')", database: openedDatabase), 4)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'ClipboardCollections'", database: openedDatabase), 1)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_items_text'", database: openedDatabase), 0)
    }

    func testSchemaFiveClipboardMetadataMigratesToOpenStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistorySchemaSix-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        let metadata = ClipboardPrivateMetadataV2(
            protectedMetadata: ClipboardProtectedMetadata(displayTitle: "Legacy private title"),
            fileURLs: ["/tmp/legacy-private-file"],
            fileBookmarks: [Data("legacy-bookmark".utf8)]
        )
        try await storage.upsertThrowing(
            ClipboardItem(type: .text, text: "open text", hash: "schema-six")
        )
        let ciphertext = try encryption.encrypt(JSONEncoder().encode(metadata))
        try await storage.execute(
            "UPDATE ClipboardItems SET protectedMetadata = x'\(hex(ciphertext))'"
        )
        try await storage.execute("DELETE FROM SchemaMigrations WHERE version = 6")
        await storage.close()

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        let history = try await reopened.loadHistoryThrowing()
        let item = try XCTUnwrap(history.first)
        XCTAssertEqual(item.protectedMetadata.displayTitle, "Legacy private title")
        XCTAssertEqual(item.fileURLs, ["/tmp/legacy-private-file"])
        XCTAssertEqual(item.fileBookmarks, [Data("legacy-bookmark".utf8)])
        await reopened.close()

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storage.databaseFile.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }
        let stored = try XCTUnwrap(dataValue("SELECT protectedMetadata FROM ClipboardItems", database: openedDatabase))
        XCTAssertEqual(try JSONDecoder().decode(ClipboardPrivateMetadataV2.self, from: stored), metadata)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM SchemaMigrations WHERE version = 6", database: openedDatabase), 1)
    }

    func testSchemaSixMigrationRollsBackWhenLegacyKeyIsUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistorySchemaSixRollback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        try await storage.upsertThrowing(
            ClipboardItem(type: .text, text: "preserved", hash: "schema-six-rollback")
        )
        let metadata = ClipboardPrivateMetadataV2(
            protectedMetadata: ClipboardProtectedMetadata(displayTitle: "Must remain recoverable")
        )
        let ciphertext = try encryption.encrypt(JSONEncoder().encode(metadata))
        try await storage.execute(
            "UPDATE ClipboardItems SET protectedMetadata = x'\(hex(ciphertext))'"
        )
        try await storage.execute("DELETE FROM SchemaMigrations WHERE version = 6")
        await storage.close()

        let unavailable = StorageService(
            baseDirectory: directory,
            keyProvider: FailingMasterKeyProvider()
        )
        do {
            _ = try await unavailable.loadHistoryThrowing()
            XCTFail("Expected the legacy key requirement to fail closed")
        } catch {}
        await unavailable.close()

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storage.databaseFile.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }
        XCTAssertEqual(
            dataValue("SELECT protectedMetadata FROM ClipboardItems", database: openedDatabase),
            ciphertext
        )
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM SchemaMigrations WHERE version = 6", database: openedDatabase), 0)
    }

    private func intValue(_ sql: String, database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func dataValue(_ sql: String, database: OpaquePointer) -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
