import Foundation
import SQLite3
import XCTest

@testable import ClipboardHistory

final class ProtectedMetadataTests: XCTestCase {
    func testProtectedMetadataRoundTripsWithoutPlaintextInSQLite() async throws {
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
        for secret in [
            "Factory alarm screenshot", "urgent", "night shift",
            "Pressure is above threshold", "local-machine-42", "#FF3300"
        ] {
            XCTAssertNil(databaseData.range(of: Data(secret.utf8)), "Found plaintext: \(secret)")
        }

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        let history = try await reopened.loadHistoryThrowing()
        let loaded = try XCTUnwrap(history.first)
        XCTAssertEqual(loaded.protectedMetadata, item.protectedMetadata)
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
        try await storage.verifyEncryptionAvailable()
        await storage.close()

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storage.databaseFile.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM SchemaMigrations WHERE version IN (1, 2, 3)", database: openedDatabase), 3)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM pragma_table_info('ClipboardItems') WHERE name IN ('protectedMetadata', 'collectionID', 'isSnippet', 'pasteboardTypes')", database: openedDatabase), 4)
        XCTAssertEqual(intValue("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'ClipboardCollections'", database: openedDatabase), 1)
    }

    private func intValue(_ sql: String, database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(statement, 0))
    }
}
