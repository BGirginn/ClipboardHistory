import Foundation
import XCTest

@testable import ClipboardHistory

final class StorageDeepCoverageTests: XCTestCase {
    func testRepositoryReconcilesPartialLegacyMalformedAndMissingRecords() async throws {
        let root = temporaryDirectory("RepositoryDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: root, encryptionService: encryption)

        let groupID = UUID()
        let storedFirst = await storage.storeImage(Data("first".utf8), id: groupID, index: 0)
        let storedSecond = await storage.storeImage(Data("second".utf8), id: groupID, index: 1)
        let firstName = try XCTUnwrap(storedFirst)
        let secondName = try XCTUnwrap(storedSecond)
        let titledID = UUID()
        let rich = ClipboardItem(type: .richText, text: "rich", hash: "rich")
        let files = ClipboardItem(
            type: .files,
            hash: "files",
            fileURLs: [root.appending(path: "file.txt").path]
        )
        let records = [
            ClipboardItem(
                id: groupID,
                type: .imageGroup,
                hash: "partial-group",
                assetFilenames: [firstName, secondName]
            ),
            ClipboardItem(type: .image, imageFilename: "missing.png", hash: "missing-image"),
            ClipboardItem(type: .pdf, hash: "missing-pdf", payloadFilename: "missing.pdf"),
            ClipboardItem(id: titledID, type: .text, text: "legacy title", hash: "legacy-title"),
            ClipboardItem(type: .text, hash: "invalid-text"),
            rich,
            files
        ]
        await storage.saveHistory(records)
        try FileManager.default.removeItem(at: storage.imagesDirectory.appending(path: secondName))
        try await storage.execute("""
            UPDATE ClipboardItems
            SET protectedMetadata = NULL, displayTitle = 'Legacy title',
                contentSubtype = 'not-a-known-subtype', assetFilenames = X'',
                fileBookmarks = X'00', pasteboardTypes = X'00',
                imageWidth = 42, imageHeight = 24, pageCount = 3, fileSize = 99
            WHERE id = '\(titledID.uuidString)'
            """)
        try await storage.execute("""
            INSERT INTO ClipboardItems (
                id, type, contentHash, createdAt, isPinned, useCount,
                contentSubtype, isSensitive, storageVersion, isEncrypted
            ) VALUES ('invalid-id', 'unknown-type', 'ignored-row', 0, 0, 0, 'unknown', 0, 1, 0)
            """)

        let loaded = try await storage.loadHistoryThrowing()
        let partial = try XCTUnwrap(loaded.first { $0.hash == "partial-group" })
        XCTAssertEqual(partial.assetFilenames, [firstName])
        XCTAssertNil(loaded.first { $0.hash == "missing-image" })
        XCTAssertNil(loaded.first { $0.hash == "missing-pdf" })
        XCTAssertNil(loaded.first { $0.hash == "invalid-text" })
        XCTAssertNotNil(loaded.first { $0.hash == "rich" })
        XCTAssertNotNil(loaded.first { $0.hash == "files" })
        let legacy = try XCTUnwrap(loaded.first { $0.hash == "legacy-title" })
        XCTAssertEqual(legacy.displayTitle, "Legacy title")
        XCTAssertEqual(legacy.contentSubtype, .unknown)
        XCTAssertEqual(legacy.imageWidth, 42)
        XCTAssertEqual(legacy.imageHeight, 24)
        XCTAssertEqual(legacy.pageCount, 3)
        XCTAssertEqual(legacy.fileSize, 99)
        XCTAssertTrue(legacy.fileBookmarks.isEmpty)
        XCTAssertTrue(legacy.pasteboardTypes.isEmpty)
        let integrityIsValid = try await storage.databaseIntegrityIsValid()
        XCTAssertTrue(integrityIsValid)

        let missingSetting = try await storage.settingValue(for: "missing-setting")
        XCTAssertNil(missingSetting)
        try await storage.setSettingValue("value", for: "covered-setting")
        let coveredSetting = try await storage.settingValue(for: "covered-setting")
        XCTAssertEqual(coveredSetting, "value")
        await assertThrowsAsync { try await storage.execute("NOT VALID SQL") }
        await storage.close()
        let databaseMessage = await storage.databaseMessage()
        XCTAssertEqual(databaseMessage, "no database")
    }

    func testCollectionsRejectInvalidNamesAndInvalidUTF8WithoutLeakingPlaintext() async throws {
        let root = temporaryDirectory("CollectionDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: root, encryptionService: encryption)
        let collection = ClipboardCollection(name: "Valid", sortOrder: 1)
        try await storage.upsertCollection(collection)
        await assertThrowsAsync { try await storage.upsertCollection(.init(name: "  \n")) }

        let invalidUTF8 = try encryption.encrypt(Data([0xFF]))
        try await storage.execute("""
            UPDATE ClipboardCollections
            SET protectedName = X'\(hex(invalidUTF8))'
            WHERE id = '\(collection.id.uuidString)'
            """)
        await assertThrowsAsync { _ = try await storage.loadCollectionsThrowing() }
        await storage.close()
    }

    func testTransactionWrappersRollbackForInsertCollectionAndDeleteFailures() async throws {
        let root = temporaryDirectory("TransactionDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        _ = await storage.loadHistory()
        let item = ClipboardItem(type: .text, text: "fail", hash: "fail")

        try await storage.execute("""
            CREATE TEMP TRIGGER fail_item_insert BEFORE INSERT ON ClipboardItems
            BEGIN SELECT RAISE(ABORT, 'injected item insert failure'); END
            """)
        await storage.saveHistory([item])
        await storage.upsert(item)
        await assertThrowsAsync { try await storage.upsertThrowing(item) }
        await assertThrowsAsync { try await storage.upsertBatchThrowing([item]) }
        await assertThrowsAsync {
            try await storage.importBatchThrowing(items: [item], collections: [])
        }
        try await storage.execute("DROP TRIGGER fail_item_insert")

        try await storage.execute("""
            CREATE TEMP TRIGGER fail_collection_insert BEFORE INSERT ON ClipboardCollections
            BEGIN SELECT RAISE(ABORT, 'injected collection insert failure'); END
            """)
        let collection = ClipboardCollection(name: "Failure")
        await assertThrowsAsync { try await storage.upsertCollection(collection) }
        await assertThrowsAsync { try await storage.upsertCollectionsBatchThrowing([collection]) }
        try await storage.execute("DROP TRIGGER fail_collection_insert")
        try await storage.upsertCollection(collection)
        let member = ClipboardItem(
            type: .text,
            text: "member",
            hash: "member",
            collectionID: collection.id
        )
        try await storage.upsertThrowing(member)

        try await storage.execute("""
            CREATE TEMP TRIGGER fail_collection_clear BEFORE UPDATE OF collectionID ON ClipboardItems
            BEGIN SELECT RAISE(ABORT, 'injected collection clear failure'); END
            """)
        await assertThrowsAsync { try await storage.deleteCollection(id: collection.id) }
        try await storage.execute("DROP TRIGGER fail_collection_clear")
        try await storage.execute("""
            CREATE TEMP TRIGGER fail_collection_delete BEFORE DELETE ON ClipboardCollections
            BEGIN SELECT RAISE(ABORT, 'injected collection delete failure'); END
            """)
        await assertThrowsAsync { try await storage.deleteCollection(id: collection.id) }
        try await storage.execute("DROP TRIGGER fail_collection_delete")

        try await storage.execute("""
            CREATE TEMP TRIGGER fail_item_delete BEFORE DELETE ON ClipboardItems
            BEGIN SELECT RAISE(ABORT, 'injected item delete failure'); END
            """)
        await assertThrowsAsync { try await storage.deleteBatchThrowing(ids: [member.id]) }
        await storage.deleteItem(member)
        await storage.clearAll()
        try await storage.execute("DROP TRIGGER fail_item_delete")
        await storage.close()
    }

    func testSensitiveGuardsClosedWrappersMetricsCleanupAndMigrationStatuses() async throws {
        let root = temporaryDirectory("StorageWrapperDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let unsafe = ClipboardItem(
            type: .text,
            text: "sensitive",
            hash: "unsafe-sensitive",
            isSensitive: true,
            isEncrypted: false
        )
        await storage.upsert(unsafe)
        await assertThrowsAsync { try await storage.upsertThrowing(unsafe) }
        await assertThrowsAsync { try await storage.upsertBatchThrowing([unsafe]) }
        await assertThrowsAsync {
            try await storage.importBatchThrowing(items: [unsafe], collections: [])
        }
        let guardedHistory = await storage.loadHistory()
        XCTAssertTrue(guardedHistory.isEmpty)
        try await storage.verifyEncryptionAvailable()

        let imageID = UUID()
        let storedImage = await storage.storeImage(Data(repeating: 1, count: 512), id: imageID)
        let imageName = try XCTUnwrap(storedImage)
        let thumbnailName = "\(imageID.uuidString.lowercased())-thumb.png"
        let storedThumbnail = await storage.storeThumbnail(
            Data(repeating: 2, count: 128),
            filename: thumbnailName,
            encrypt: false
        )
        XCTAssertTrue(storedThumbnail)
        let storedPayload = await storage.storePayload(
            Data(repeating: 3, count: 256),
            id: imageID,
            extension: "pdf",
            encrypt: false
        )
        let payloadName = try XCTUnwrap(storedPayload)
        let old = Date.now.addingTimeInterval(-100 * 86_400)
        let image = ClipboardItem(
            id: imageID,
            type: .image,
            imageFilename: imageName,
            creationDate: old,
            hash: "old-image",
            thumbnailFilename: thumbnailName,
            payloadFilename: payloadName
        )
        let recent = ClipboardItem(type: .text, text: "recent", hash: "recent")
        await storage.saveHistory([image, recent])
        let associatedFileSize = await storage.associatedFileSize(for: image)
        let unsafeLogicalSize = await storage.logicalFileSize(
            "../unsafe",
            directory: storage.imagesDirectory
        )
        XCTAssertGreaterThan(associatedFileSize, 0)
        XCTAssertEqual(unsafeLogicalSize, 0)
        let metrics = await storage.storageMetrics()
        XCTAssertGreaterThan(metrics.totalBytes, 0)
        XCTAssertNotNil(storage.imageURL(filename: imageName))
        XCTAssertNil(storage.imageURL(filename: "../unsafe"))
        XCTAssertNotNil(storage.payloadURL(filename: payloadName))
        XCTAssertNil(storage.payloadURL(filename: "../unsafe"))
        let cleanup = await storage.cleanup(
            historyLimit: 1,
            retentionDays: 30,
            imageRetentionDays: 14,
            maximumStorageBytes: 0
        )
        XCTAssertGreaterThanOrEqual(cleanup.removedItemCount, 1)

        let initialMigrationStatus = await storage.migrationStatus()
        XCTAssertTrue(initialMigrationStatus.contains("no legacy migration"))
        try await storage.setSettingValue("1", for: "jsonMigrationCompleted")
        let completedMigrationStatus = await storage.migrationStatus()
        XCTAssertTrue(completedMigrationStatus.contains("migration complete"))
        try await storage.setSettingValue("failed", for: "jsonMigrationStatus")
        let failedMigrationStatus = await storage.migrationStatus()
        XCTAssertTrue(failedMigrationStatus.contains("preserved after failure"))
        let historyForMigration = await storage.loadHistory()
        await storage.migrateEncryption(items: historyForMigration, mode: .all)

        await storage.close()
        await storage.close()
        let closedHistory = await storage.loadHistory()
        XCTAssertTrue(closedHistory.isEmpty)
        await storage.upsert(recent)
        await storage.deleteItem(recent)
        await storage.clearAll()
        let closedCleanup = await storage.cleanup(
            historyLimit: 1,
            retentionDays: 1,
            imageRetentionDays: 1,
            maximumStorageBytes: 1
        )
        XCTAssertEqual(closedCleanup, CleanupReport(removedItemCount: 0, reclaimedBytes: 0))
        let closedMigrationStatus = await storage.migrationStatus()
        XCTAssertEqual(closedMigrationStatus, "Database unavailable")
        await storage.migrateEncryption(items: [recent], mode: .all)
    }

    func testKeyProviderRotationAndDefaultStorageSelectionDoNotRequireAppleAccount() async throws {
        let root = temporaryDirectory("KeyProviderRotationCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = RecordingMasterKeyProvider(key: Data(repeating: 4, count: 32))
        let storage = StorageService(baseDirectory: root, keyProvider: provider)
        await storage.clearAll()
        XCTAssertEqual(provider.loadCount, 1)
        XCTAssertEqual(provider.replacementCount, 1)
        try await storage.verifyEncryptionAvailable()
        await storage.close()

        let defaultStorage = StorageService()
        await defaultStorage.close()
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func assertThrowsAsync(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected operation to throw", file: file, line: line)
        } catch {}
    }

}

private final class RecordingMasterKeyProvider: MasterKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data
    private(set) var loadCount = 0
    private(set) var replacementCount = 0

    init(key: Data) {
        self.key = key
    }

    func loadOrCreateKey() throws -> Data {
        lock.withLock {
            loadCount += 1
            return key
        }
    }

    func replaceKey(with newKey: Data) throws {
        lock.withLock {
            replacementCount += 1
            key = newKey
        }
    }
}
