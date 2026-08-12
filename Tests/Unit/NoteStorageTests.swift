import Foundation
import SQLite3
import XCTest
@testable import ClipboardHistory

final class NoteStorageTests: XCTestCase {
    private var directory: URL!
    private var storage: StorageService!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(
            path: "NoteStorageTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        storage = StorageService(baseDirectory: directory)
    }

    override func tearDown() async throws {
        await storage?.close()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        storage = nil
        directory = nil
        try await super.tearDown()
    }

    func testCRUDAndUpdatedAtSorting() async throws {
        let older = Note(
            title: "Older",
            body: "First body",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        var newer = Note(
            title: nil,
            body: "Generated title\nSecond body",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        try await storage.upsertNotesBatchThrowing([older, newer])
        var loaded = try await storage.loadNotesThrowing()

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.first?.resolvedTitle, "Generated title")

        newer.title = "Updated"
        newer.updatedAt = Date(timeIntervalSince1970: 50)
        try await storage.upsertNoteThrowing(newer)
        loaded = try await storage.loadNotesThrowing()
        XCTAssertEqual(loaded.first?.title, "Updated")

        try await storage.deleteNoteThrowing(id: older.id)
        loaded = try await storage.loadNotesThrowing()
        XCTAssertEqual(loaded.map(\.id), [newer.id])
    }

    func testV3DatabaseMigratesToV4NotesSchema() async throws {
        _ = try await storage.loadNotesThrowing()
        await storage.close()
        try mutateDatabase { database in
            XCTAssertEqual(sqlite3_exec(database, "DROP TABLE Notes", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(
                sqlite3_exec(database, "DELETE FROM SchemaMigrations WHERE version = 4", nil, nil, nil),
                SQLITE_OK
            )
        }

        storage = StorageService(baseDirectory: directory)
        let migratedNotes = try await storage.loadNotesThrowing()
        XCTAssertEqual(migratedNotes, [])
        XCTAssertTrue(try databaseContainsMigration(4))
        XCTAssertTrue(try databaseContainsTable("Notes"))
    }

    func testNotePlaintextNeverAppearsInSQLite() async throws {
        let title = "private-note-title-\(UUID().uuidString)"
        let body = "private-note-body-\(UUID().uuidString)"
        try await storage.upsertNoteThrowing(Note(title: title, body: body))
        await storage.close()

        let databaseData = try Data(contentsOf: storage.databaseFile)
        XCTAssertNil(databaseData.range(of: Data(title.utf8)))
        XCTAssertNil(databaseData.range(of: Data(body.utf8)))
    }

    func testClearHistoryPreservesNotesAndUsesSeparateEncryption() async throws {
        await storage.close()
        let historyEncryption = try EncryptionService(keyData: Data(repeating: 0x11, count: 32))
        let noteEncryption = try EncryptionService(keyData: Data(repeating: 0x22, count: 32))
        storage = StorageService(
            baseDirectory: directory,
            encryptionService: historyEncryption,
            noteEncryptionService: noteEncryption
        )
        let note = Note(
            title: "Protected note",
            body: "Notes survive history erasure",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await storage.upsertNoteThrowing(note)
        await storage.upsert(
            ClipboardItem(
                type: .text,
                text: "Encrypted history",
                hash: "separate-history-key",
                isSensitive: true,
                isEncrypted: true
            )
        )
        let blobs = try readNoteBlobs()

        XCTAssertThrowsError(try historyEncryption.decrypt(blobs.title))
        XCTAssertEqual(try noteEncryption.decrypt(blobs.title), Data(note.title!.utf8))
        XCTAssertEqual(try noteEncryption.decrypt(blobs.body), Data(note.body.utf8))

        _ = try await storage.clearAll()

        let history = await storage.loadHistory()
        let notes = try await storage.loadNotesThrowing()
        XCTAssertEqual(history, [])
        XCTAssertEqual(notes, [note])
    }

    func testNoteSizeLimitsFailClosed() async throws {
        let longTitle = String(repeating: "a", count: Note.maximumTitleLength + 1)
        let longBody = String(repeating: "b", count: Note.maximumBodyBytes + 1)

        await XCTAssertThrowsErrorAsync {
            try await self.storage.upsertNoteThrowing(Note(title: longTitle, body: "body"))
        }
        await XCTAssertThrowsErrorAsync {
            try await self.storage.upsertNoteThrowing(Note(body: longBody))
        }
        let notes = try await storage.loadNotesThrowing()
        XCTAssertEqual(notes, [])
    }

    private func readNoteBlobs() throws -> (title: Data, body: Data) {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storage.databaseFile.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        guard let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(database, "SELECT protectedTitle, protectedBody FROM Notes LIMIT 1", -1, &statement, nil),
            SQLITE_OK
        )
        guard let statement else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
        return (try blob(statement, column: 0), try blob(statement, column: 1))
    }

    private func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Data(bytes: bytes, count: count)
    }

    private func mutateDatabase(_ mutation: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(storage.databaseFile.path, &database), SQLITE_OK)
        guard let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }
        try mutation(database)
    }

    private func databaseContainsMigration(_ version: Int) throws -> Bool {
        try queryExists("SELECT 1 FROM SchemaMigrations WHERE version = \(version)")
    }

    private func databaseContainsTable(_ name: String) throws -> Bool {
        try queryExists("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(name)'")
    }

    private func queryExists(_ sql: String) throws -> Bool {
        var result = false
        try mutateDatabase { database in
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
            guard let statement else { return }
            defer { sqlite3_finalize(statement) }
            result = sqlite3_step(statement) == SQLITE_ROW
        }
        return result
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
