import Foundation
import SQLite3
import XCTest

@testable import ClipboardHistory

final class StorageFailClosedTests: XCTestCase {
    private struct InjectedFailure: Error {}
    func testManagedFilenameRejectsTraversalAndSeparators() {
        XCTAssertNil(ManagedFilename(""))
        XCTAssertNil(ManagedFilename("."))
        XCTAssertNil(ManagedFilename(".."))
        XCTAssertNil(ManagedFilename("../history.sqlite3"))
        XCTAssertNil(ManagedFilename("folder/asset.png"))
        XCTAssertNil(ManagedFilename("folder\\asset.png"))
        XCTAssertNil(ManagedFilename("volume:asset.png"))
        XCTAssertNil(ManagedFilename("asset\0.png"))
        XCTAssertNotNil(ManagedFilename("safe-asset.png"))
    }

    func testEncryptedAssetNeverFallsBackToPlaintext() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryFailClosed-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let filename = "asset.png"
        try FileManager.default.createDirectory(
            at: storage.imagesDirectory,
            withIntermediateDirectories: true
        )
        try Data("plaintext".utf8).write(
            to: storage.imagesDirectory.appending(path: filename),
            options: .atomic
        )

        let loaded = await storage.imageData(filename: filename, isEncrypted: true)

        XCTAssertNil(loaded)
    }

    func testTamperedEncryptedTextFailsTheWholeLoad() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryTamperedText-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        let item = ClipboardItem(
            type: .text,
            text: "protected",
            hash: "protected-hash",
            isEncrypted: true
        )
        await storage.upsert(item)
        await storage.close()

        let database = try XCTUnwrap(openDatabase(at: storage.databaseFile))
        defer { sqlite3_close(database) }
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "UPDATE ClipboardItems SET textContent = x'00010203' WHERE id = '\(item.id.uuidString)'",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        do {
            _ = try await reopened.loadHistoryThrowing()
            XCTFail("Tampered ciphertext must not be presented as empty history.")
        } catch EncryptionServiceError.invalidCiphertext {
            // Expected: the entire load fails closed instead of returning a blank record.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInjectedSQLiteFailureRollsBackThrowingUpsert() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryInjectedSQLite-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(
            baseDirectory: directory,
            operationFailureInjector: { operation in
                guard case let .prepareSQL(sql) = operation,
                      sql.contains("INSERT OR REPLACE INTO ClipboardItems") else { return }
                throw InjectedFailure()
            }
        )

        do {
            try await storage.upsertThrowing(
                ClipboardItem(type: .text, text: "must rollback", hash: "rollback")
            )
            XCTFail("Expected the injected database failure.")
        } catch is InjectedFailure {
            // Expected.
        }
        let loaded = await storage.loadHistory()
        XCTAssertTrue(loaded.isEmpty)
    }

    @MainActor
    func testViewModelDoesNotPresentItemWhenPersistenceFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryViewModelSQLiteFailure-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(
            baseDirectory: directory,
            operationFailureInjector: { operation in
                guard case let .prepareSQL(sql) = operation,
                      sql.contains("INSERT OR REPLACE INTO ClipboardItems") else { return }
                throw InjectedFailure()
            }
        )
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            startsAutomatically: false
        )

        await viewModel.insert(.text(value: "not persisted", hash: "not-persisted"))

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func openDatabase(at url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return nil
        }
        return database
    }
}
