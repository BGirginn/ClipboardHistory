import Foundation
import XCTest
@testable import ClipboardHistory

final class DatabaseMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(
            path: "DatabaseMigrationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try await super.tearDown()
    }

    func testJSONMigrationPreservesMetadataAndAssetsAndIsIdempotent() async throws {
        let images = directory.appending(path: "Images", directoryHint: .isDirectory)
        let thumbnails = directory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let pinned = created.addingTimeInterval(60)
        let item = ClipboardItem(
            type: .image,
            imageFilename: "legacy.png",
            creationDate: created,
            hash: "legacy-hash",
            isPinned: true,
            pinnedAt: pinned,
            lastUsedAt: pinned,
            useCount: 7,
            thumbnailFilename: "legacy-thumb.png",
            contentSubtype: .image
        )
        try Data([1, 2, 3]).write(to: images.appending(path: "legacy.png"))
        try Data([4, 5]).write(to: thumbnails.appending(path: "legacy-thumb.png"))
        try JSONEncoder().encode([item]).write(
            to: directory.appending(path: "history.json"),
            options: .atomic
        )

        let storage = StorageService(baseDirectory: directory)
        let first = await storage.loadHistory()
        let second = await storage.loadHistory()

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first.first?.hash, item.hash)
        XCTAssertEqual(first.first?.isPinned, true)
        XCTAssertEqual(first.first?.useCount, 7)
        let migratedItem = try XCTUnwrap(first.first)
        XCTAssertEqual(migratedItem.creationDate.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appending(path: "legacy.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnails.appending(path: "legacy-thumb.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.historyFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.databaseFile.path))
        let backups = try FileManager.default.contentsOfDirectory(at: storage.backupsDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(backups.contains { $0.lastPathComponent.hasPrefix("history-before-sqlite-") })
        XCTAssertTrue(backups.contains { $0.lastPathComponent.hasPrefix("history-migrated-") })
        await storage.close()
    }

    func testFailedMigrationRollsBackAndDatabaseRemainsUsable() async throws {
        let legacy = ClipboardItem(type: .text, text: "legacy", hash: "legacy")
        try JSONEncoder().encode([legacy]).write(
            to: directory.appending(path: "history.json"),
            options: .atomic
        )
        struct SimulatedFailure: Error {}
        let storage = StorageService(
            baseDirectory: directory,
            migrationFailureInjector: { throw SimulatedFailure() }
        )

        let afterFailure = await storage.loadHistory()
        XCTAssertTrue(afterFailure.isEmpty)
        await storage.upsert(ClipboardItem(type: .text, text: "new", hash: "new"))
        let usableHistory = await storage.loadHistory()
        let status = await storage.migrationStatus()
        XCTAssertEqual(usableHistory.map(\.hash), ["new"])
        XCTAssertTrue(status.contains("preserved after failure"))
        await storage.close()
    }

    func testCorruptDatabaseIsPreservedAndRecreated() async throws {
        let first = StorageService(baseDirectory: directory)
        await first.upsert(ClipboardItem(type: .text, text: "before", hash: "before"))
        await first.close()
        try Data("not a sqlite database".utf8).write(to: first.databaseFile, options: .atomic)

        let recovered = StorageService(baseDirectory: directory)
        let recoveredHistory = await recovered.loadHistory()
        XCTAssertTrue(recoveredHistory.isEmpty)
        await recovered.upsert(ClipboardItem(type: .text, text: "after", hash: "after"))
        let newHistory = await recovered.loadHistory()
        XCTAssertEqual(newHistory.first?.hash, "after")
        let backups = try FileManager.default.contentsOfDirectory(at: recovered.backupsDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(backups.contains { $0.lastPathComponent.hasPrefix("history-corrupt-") })
        await recovered.close()
    }

    func testStartupRemovesAbandonedStagingAndOrphanRecord() async throws {
        let storage = StorageService(baseDirectory: directory)
        await storage.saveHistory([
            ClipboardItem(type: .image, imageFilename: "missing.png", hash: "missing")
        ])
        let abandoned = storage.stagingDirectory.appending(path: "abandoned.tmp")
        try Data([1]).write(to: abandoned)
        await storage.close()
        let restarted = StorageService(baseDirectory: directory)

        let loaded = await restarted.loadHistory()

        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        await restarted.close()
    }
}
