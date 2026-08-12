import AppKit
import Foundation
import SQLite3
import XCTest
@testable import ClipboardHistory

final class StorageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: StorageService!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        storage = StorageService(baseDirectory: temporaryDirectory)
    }

    override func tearDown() async throws {
        await storage?.close()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        storage = nil
        temporaryDirectory = nil
        try await super.tearDown()
    }

    func testHistoryRoundTrip() async throws {
        let item = ClipboardItem(type: .text, text: "saved", hash: "hash")
        await storage.saveHistory([item])

        let loaded = await storage.loadHistory()

        XCTAssertEqual(loaded.first?.id, item.id)
        XCTAssertEqual(loaded.first?.text, item.text)
        XCTAssertEqual(loaded.first?.hash, item.hash)
        XCTAssertEqual(
            loaded.first?.creationDate.timeIntervalSince1970 ?? 0,
            item.creationDate.timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(try readOptimizedNullColumnCount(), 4)
    }

    func testImageRoundTripAndClear() async throws {
        let data = try XCTUnwrap(makePNGData())
        let id = UUID()
        let filename = await storage.storeImage(data, id: id)
        let storedFilename = try XCTUnwrap(filename)

        let loadedImageData = await storage.imageData(filename: storedFilename)
        XCTAssertEqual(loadedImageData, data)

        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFilename: storedFilename,
            hash: HashUtility.sha256(data: data)
        )
        await storage.saveHistory([item])
        _ = try await storage.clearAll()

        let clearedHistory = await storage.loadHistory()
        let clearedImageData = await storage.imageData(filename: storedFilename)
        XCTAssertEqual(clearedHistory, [])
        XCTAssertNil(clearedImageData)
    }

    func testCorruptJSONIsRecoveredWithoutThrowing() async throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try Data("not valid json".utf8).write(to: storage.historyFile, options: .atomic)

        let loaded = await storage.loadHistory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: storage.backupsDirectory,
            includingPropertiesForKeys: nil
        )

        XCTAssertTrue(loaded.isEmpty)
        XCTAssertTrue(contents.contains { $0.lastPathComponent.hasPrefix("history-migration-failed-") })
    }

    func testClearDoesNotRotateTheLegacyClipboardKey() async throws {
        await storage.close()
        let knownEncryption = try EncryptionService(keyData: Data(repeating: 0x5A, count: 32))
        storage = StorageService(
            baseDirectory: temporaryDirectory,
            encryptionService: knownEncryption
        )
        let firstPlaintext = Data("first encrypted value".utf8)
        await storage.upsert(
            ClipboardItem(
                type: .text,
                text: String(decoding: firstPlaintext, as: UTF8.self),
                hash: "first-encrypted",
                isSensitive: true,
                isEncrypted: true
            )
        )
        let firstCiphertext = try readNewestTextBlob()
        XCTAssertEqual(try knownEncryption.decrypt(firstCiphertext), firstPlaintext)

        _ = try await storage.clearAll()
        let secondPlaintext = Data("second encrypted value".utf8)
        await storage.upsert(
            ClipboardItem(
                type: .text,
                text: String(decoding: secondPlaintext, as: UTF8.self),
                hash: "second-encrypted",
                isSensitive: true,
                isEncrypted: true
            )
        )
        let secondCiphertext = try readNewestTextBlob()

        XCTAssertEqual(try knownEncryption.decrypt(secondCiphertext), secondPlaintext)
        XCTAssertNil(secondCiphertext.range(of: secondPlaintext))
    }

    func testClearReportsResidualCleanupAndStartupFinishesCommittedQuarantine() async throws {
        enum InjectedFailure: Error { case cleanup }
        await storage.close()
        storage = StorageService(
            baseDirectory: temporaryDirectory,
            encryptionService: .ephemeral(),
            operationFailureInjector: { operation in
                if case let .removeAsset(name) = operation, name.hasPrefix("clear-") {
                    throw InjectedFailure.cleanup
                }
            }
        )
        let item = ClipboardItem(type: .text, text: "clear me", hash: "clear-me")
        try await storage.upsertThrowing(item)

        let outcome = try await storage.clearAll()

        XCTAssertTrue(outcome.persistentChangeCommitted)
        XCTAssertTrue(outcome.requiresCleanupRetry)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(
            at: storage.operationsDirectory,
            includingPropertiesForKeys: nil
        )).contains { $0.lastPathComponent.hasPrefix("clear-") })
        await storage.close()

        storage = StorageService(
            baseDirectory: temporaryDirectory,
            encryptionService: .ephemeral()
        )
        let recoveredHistory = try await storage.loadHistoryThrowing()
        XCTAssertTrue(recoveredHistory.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: storage.operationsDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    private func makePNGData() -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        ) else { return nil }

        bitmap.setColor(
            NSColor(deviceRed: 0.1, green: 0.3, blue: 0.9, alpha: 1),
            atX: 0,
            y: 0
        )
        return bitmap.representation(using: .png, properties: [:])
    }

    private func readNewestTextBlob() throws -> Data {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                storage.databaseFile.path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            ),
            SQLITE_OK
        )
        guard let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "SELECT textContent FROM ClipboardItems ORDER BY createdAt DESC LIMIT 1",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        guard let statement else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CocoaError(.fileReadUnknown)
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Data(bytes: bytes, count: count)
    }

    private func readOptimizedNullColumnCount() throws -> Int {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                storage.databaseFile.path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            ),
            SQLITE_OK
        )
        guard let database else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT (assetFilenames IS NULL) + (fileURLs IS NULL) +
                       (fileBookmarks IS NULL) + (protectedMetadata IS NULL) +
                       (pasteboardTypes IS NULL)
                FROM ClipboardItems LIMIT 1
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        guard let statement else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CocoaError(.fileReadUnknown)
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
