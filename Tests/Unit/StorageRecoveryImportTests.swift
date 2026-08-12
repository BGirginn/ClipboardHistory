import Foundation
import XCTest

@testable import ClipboardHistory

private struct FixedMasterKeyProvider: MasterKeyProvider {
    let key: Data

    func loadOrCreateKey() throws -> Data { key }
    func replaceKey(with newKey: Data) throws {}
}

final class StorageRecoveryImportTests: XCTestCase {
    func testVerifiedMigrationAtomicallyReplacesAndPreservesRollbackBackup() async throws {
        let root = temporaryDirectory("StorageRecoveryImport")
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
        let note = Note(
            title: "Recovered note",
            body: "Encrypted recovery keeps notes",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await sourceStorage.upsertThrowing(item)
        try await sourceStorage.upsertNoteThrowing(note)
        let archiveURL = root.appending(path: "migration.clipboardarchive")
        try await ExportImportService().exportArchive(
            items: [item],
            storage: sourceStorage,
            to: archiveURL,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            collections: [collection],
            notes: [note],
            password: "migration-password"
        )
        await sourceStorage.close()

        let keyProvider = FixedMasterKeyProvider(key: Data(repeating: 0x47, count: 32))
        let noteKeyProvider = FixedMasterKeyProvider(key: Data(repeating: 0x48, count: 32))
        let result = try await StorageRecoveryImportService(
            keyProvider: keyProvider,
            noteKeyProvider: noteKeyProvider
        ).migrate(
            encryptedArchive: archiveURL,
            password: "migration-password",
            to: destination
        )

        let backup = try XCTUnwrap(result.rollbackBackupURL)
        XCTAssertEqual(result.importedItemCount, 1)
        XCTAssertEqual(result.importedNoteCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appending(path: marker.lastPathComponent).path))
        let migratedStorage = StorageService(
            baseDirectory: destination,
            keyProvider: keyProvider,
            noteKeyProvider: noteKeyProvider
        )
        let history = try await migratedStorage.loadHistoryThrowing()
        let collections = try await migratedStorage.loadCollectionsThrowing()
        let notes = try await migratedStorage.loadNotesThrowing()
        XCTAssertEqual(history.first?.text, item.text)
        XCTAssertTrue(history.first?.isEncrypted == false)
        XCTAssertEqual(collections.first?.name, collection.name)
        XCTAssertEqual(notes, [note])
        await migratedStorage.close()
    }

    func testWrongPasswordNeverReplacesExistingDestination() async throws {
        let root = temporaryDirectory("StorageRecoveryImportWrongPassword")
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
            _ = try await StorageRecoveryImportService().migrate(
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

    func testDestinationSymlinkIsRejectedBeforeArchiveAccess() async throws {
        let root = temporaryDirectory("StorageRecoverySymlink")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        let destination = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        do {
            _ = try await StorageRecoveryImportService().migrate(
                encryptedArchive: root.appending(path: "unused.clipboardarchive"),
                password: "password",
                to: destination,
                keyProvider: FixedMasterKeyProvider(key: Data(repeating: 1, count: 32))
            )
            XCTFail("Expected destination symlink rejection")
        } catch ExportImportError.unsafePath {
            // Expected.
        }
    }

    func testFailedFinalMoveRestoresBackupAndRemovesStaging() async throws {
        let root = temporaryDirectory("StorageRecoveryMoveRollback")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceStorage = StorageService(
            baseDirectory: root.appending(path: "Source"),
            encryptionService: .ephemeral()
        )
        let item = ClipboardItem(type: .text, text: "new", hash: "new")
        let archive = root.appending(path: "migration.clipboardarchive")
        try await ExportImportService().exportArchive(
            items: [item],
            storage: sourceStorage,
            to: archive,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            password: "password"
        )
        await sourceStorage.close()
        let destination = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let marker = destination.appending(path: "old-marker")
        try Data("old".utf8).write(to: marker)
        let fileSystem = FailingFinalMoveFileSystem(destination: destination)
        let service = StorageRecoveryImportService(fileSystem: fileSystem)

        do {
            _ = try await service.migrate(
                encryptedArchive: archive,
                password: "password",
                to: destination,
                keyProvider: FixedMasterKeyProvider(key: Data(repeating: 2, count: 32))
            )
            XCTFail("Expected final staging move failure")
        } catch let error as StorageRecoveryError {
            XCTAssertTrue(error.previousDatabaseRestored)
            XCTAssertEqual(try Data(contentsOf: marker), Data("old".utf8))
            XCTAssertEqual(fileSystem.injectedFailureCount, 1)
            XCTAssertEqual(fileSystem.removedStagingCount, 1)
        }
    }

    func testFailedFinalMoveReportsUnverifiedRollbackSeparately() async throws {
        let root = temporaryDirectory("StorageRecoveryRollbackFailure")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceStorage = StorageService(
            baseDirectory: root.appending(path: "Source"),
            encryptionService: .ephemeral()
        )
        let item = ClipboardItem(type: .text, text: "new", hash: "new")
        let archive = root.appending(path: "migration.clipboardarchive")
        try await ExportImportService().exportArchive(
            items: [item],
            storage: sourceStorage,
            to: archive,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            password: "password"
        )
        await sourceStorage.close()
        let destination = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "old-marker"))
        let fileSystem = FailingFinalMoveFileSystem(
            destination: destination,
            failsRollback: true
        )

        do {
            _ = try await StorageRecoveryImportService(fileSystem: fileSystem).migrate(
                encryptedArchive: archive,
                password: "password",
                to: destination,
                keyProvider: FixedMasterKeyProvider(key: Data(repeating: 3, count: 32))
            )
            XCTFail("Expected rollback verification failure")
        } catch let error as StorageRecoveryError {
            XCTAssertFalse(error.previousDatabaseRestored)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(fileSystem.rollbackFailureCount, 1)
        }
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

private final class FailingFinalMoveFileSystem: MigrationFileSystem, @unchecked Sendable {
    struct ExpectedFailure: Error {}
    struct RollbackFailure: Error {}

    private let local = LocalMigrationFileSystem()
    private let destination: URL
    private let failsRollback: Bool
    private(set) var injectedFailureCount = 0
    private(set) var removedStagingCount = 0
    private(set) var rollbackFailureCount = 0

    init(destination: URL, failsRollback: Bool = false) {
        self.destination = destination.standardizedFileURL
        self.failsRollback = failsRollback
    }

    func fileExists(at url: URL) -> Bool {
        local.fileExists(at: url)
    }

    func isSymbolicLink(at url: URL) throws -> Bool {
        try local.isSymbolicLink(at: url)
    }

    func createDirectory(at url: URL) throws {
        try local.createDirectory(at: url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        if source.lastPathComponent.hasPrefix(".ClipboardHistory-recovery-import-"),
           destination.standardizedFileURL == self.destination,
           injectedFailureCount == 0 {
            injectedFailureCount += 1
            throw ExpectedFailure()
        }
        if failsRollback,
           source.lastPathComponent.hasPrefix("before-recovery-import-"),
           destination.standardizedFileURL == self.destination {
            rollbackFailureCount += 1
            throw RollbackFailure()
        }
        try local.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        if url.lastPathComponent.hasPrefix(".ClipboardHistory-recovery-import-") {
            removedStagingCount += 1
        }
        try local.removeItem(at: url)
    }
}
