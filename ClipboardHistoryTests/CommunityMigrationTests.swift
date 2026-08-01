import Foundation
import XCTest

@testable import ClipboardHistory

private struct FixedMasterKeyProvider: MasterKeyProvider {
    let key: Data

    func loadOrCreateKey() throws -> Data { key }
    func replaceKey(with newKey: Data) throws {}
}

final class CommunityMigrationTests: XCTestCase {
    func testVerifiedMigrationAtomicallyReplacesAndPreservesRollbackBackup() async throws {
        let root = temporaryDirectory("CommunityMigration")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appending(path: "Source", directoryHint: .isDirectory)
        let destination = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let marker = destination.appending(path: "old-database-marker")
        try Data("preserve me".utf8).write(to: marker)

        let sourceStorage = StorageService(
            baseDirectory: sourceRoot,
            encryptionService: .ephemeral()
        )
        let collection = ClipboardCollection(name: "Encrypted Collection")
        let item = ClipboardItem(
            type: .text,
            text: "migrated value",
            hash: "migrated-hash",
            collectionID: collection.id
        )
        try await sourceStorage.upsertThrowing(item)
        let archiveURL = root.appending(path: "migration.clipboardarchive")
        try await ExportImportService().exportArchive(
            items: [item],
            storage: sourceStorage,
            to: archiveURL,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            collections: [collection],
            password: "migration-password"
        )
        await sourceStorage.close()

        let keyProvider = FixedMasterKeyProvider(key: Data(repeating: 0x47, count: 32))
        let result = try await CommunityMigrationService().migrate(
            encryptedArchive: archiveURL,
            password: "migration-password",
            to: destination,
            keyProvider: keyProvider
        )

        let backup = try XCTUnwrap(result.rollbackBackupURL)
        XCTAssertEqual(result.importedItemCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appending(path: marker.lastPathComponent).path))
        let migratedStorage = StorageService(baseDirectory: destination, keyProvider: keyProvider)
        let history = try await migratedStorage.loadHistoryThrowing()
        let collections = try await migratedStorage.loadCollectionsThrowing()
        XCTAssertEqual(history.first?.text, item.text)
        XCTAssertTrue(history.first?.isEncrypted == true)
        XCTAssertEqual(collections.first?.name, collection.name)
        await migratedStorage.close()
    }

    func testWrongPasswordNeverReplacesExistingDestination() async throws {
        let root = temporaryDirectory("CommunityMigrationWrongPassword")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceStorage = StorageService(
            baseDirectory: root.appending(path: "Source"),
            encryptionService: .ephemeral()
        )
        let item = ClipboardItem(type: .text, text: "value", hash: "value")
        let archiveURL = root.appending(path: "migration.clipboardarchive")
        try await ExportImportService().exportArchive(
            items: [item],
            storage: sourceStorage,
            to: archiveURL,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            password: "correct-password"
        )
        await sourceStorage.close()
        let destination = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let marker = destination.appending(path: "must-remain")
        try Data([1, 2, 3]).write(to: marker)

        do {
            _ = try await CommunityMigrationService().migrate(
                encryptedArchive: archiveURL,
                password: "wrong-password",
                to: destination,
                keyProvider: FixedMasterKeyProvider(key: Data(repeating: 0x22, count: 32))
            )
            XCTFail("Expected authenticated archive verification to fail.")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            XCTAssertEqual(try Data(contentsOf: marker), Data([1, 2, 3]))
        }
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
