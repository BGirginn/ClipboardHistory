import Foundation
import XCTest

@testable import ClipboardHistory

final class ExportImportDeepCoverageTests: XCTestCase {
    func testMetadataOnlyExportRedactsEveryPayloadAndCannotBeImported() async throws {
        let root = temporaryDirectory("MetadataOnlyExportCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let item = ClipboardItem(
            type: .text,
            text: "secret text",
            imageFilename: "image.png",
            hash: "metadata-only",
            thumbnailFilename: "thumb.png",
            payloadFilename: "payload.rtf",
            assetFilenames: ["group.png"],
            fileURLs: ["/tmp/file"],
            fileBookmarks: [Data([1])],
            isEncrypted: true
        )
        let excludedSensitive = ClipboardItem(
            type: .text,
            text: "never export",
            hash: "excluded-sensitive",
            isSensitive: true
        )
        let excludedFiles = ClipboardItem(
            type: .files,
            hash: "excluded-files",
            fileURLs: ["/tmp/file"]
        )
        let destination = root.appending(path: "metadata.clipboardarchive")
        let service = ExportImportService()
        try await service.exportArchive(
            items: [item, excludedSensitive, excludedFiles],
            storage: storage,
            to: destination,
            mode: .metadataOnly,
            includeImagesAndDocuments: false,
            includeFileReferences: false
        )
        let archive = try decodeArchive(at: destination)
        let redacted = try XCTUnwrap(archive.items.first)
        XCTAssertEqual(archive.items.count, 1)
        XCTAssertNil(redacted.text)
        XCTAssertNil(redacted.imageFilename)
        XCTAssertNil(redacted.thumbnailFilename)
        XCTAssertNil(redacted.payloadFilename)
        XCTAssertTrue(redacted.assetFilenames.isEmpty)
        XCTAssertTrue(redacted.fileURLs.isEmpty)
        XCTAssertTrue(redacted.fileBookmarks.isEmpty)
        XCTAssertFalse(redacted.isEncrypted)
        await assertThrowsAsync {
            _ = try await service.importArchive(
                from: destination,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }
        await storage.close()
    }

    func testFullExportCollectsImageGroupPayloadAndCollectionAssets() async throws {
        let sourceRoot = temporaryDirectory("FullAssetExportSource")
        let destinationRoot = temporaryDirectory("FullAssetExportDestination")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let source = StorageService(baseDirectory: sourceRoot, encryptionService: .ephemeral())
        let destination = StorageService(baseDirectory: destinationRoot, encryptionService: .ephemeral())
        let imageID = UUID()
        let storedImage = await source.storeImage(Data("image".utf8), id: imageID)
        let imageName = try XCTUnwrap(storedImage)
        let groupID = UUID()
        let storedGroup0 = await source.storeImage(Data("group-0".utf8), id: groupID, index: 0)
        let storedGroup1 = await source.storeImage(Data("group-1".utf8), id: groupID, index: 1)
        let group0 = try XCTUnwrap(storedGroup0)
        let group1 = try XCTUnwrap(storedGroup1)
        let pdfID = UUID()
        let storedPayload = await source.storePayload(
            Data("%PDF-1.7\npayload".utf8),
            id: pdfID,
            extension: "pdf",
            encrypt: false
        )
        let payloadName = try XCTUnwrap(storedPayload)
        let items = [
            ClipboardItem(id: imageID, type: .image, imageFilename: imageName, hash: "image"),
            ClipboardItem(
                id: groupID,
                type: .imageGroup,
                hash: "group",
                assetFilenames: [group0, group1]
            ),
            ClipboardItem(id: pdfID, type: .pdf, hash: "pdf", payloadFilename: payloadName)
        ]
        let collection = ClipboardCollection(name: "Archive Collection", sortOrder: 4)
        let archiveURL = sourceRoot.appending(path: "assets.clipboardarchive")
        let service = ExportImportService()
        try await service.exportArchive(
            items: items,
            storage: source,
            to: archiveURL,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: true,
            collections: [collection]
        )
        let archive = try decodeArchive(at: archiveURL)
        XCTAssertEqual(archive.assets.count, 4)
        XCTAssertEqual(archive.assetHashes.count, 4)
        XCTAssertEqual(archive.collectionHashes.count, 1)

        let report = try await service.importArchive(
            from: archiveURL,
            storage: destination,
            existingItems: [],
            encryptionMode: .all
        )
        XCTAssertEqual(report, ImportReport(importedCount: 3, duplicateCount: 0, rejectedCount: 0))
        let imported = await destination.loadHistory()
        XCTAssertEqual(imported.count, 3)
        XCTAssertTrue(imported.allSatisfy(\.isEncrypted))
        let importedCollections = try await destination.loadCollectionsThrowing()
        XCTAssertEqual(importedCollections.first?.id, collection.id)
        XCTAssertEqual(importedCollections.first?.name, collection.name)
        XCTAssertEqual(importedCollections.first?.sortOrder, collection.sortOrder)
        XCTAssertEqual(
            importedCollections.first?.creationDate.timeIntervalSince1970 ?? 0,
            collection.creationDate.timeIntervalSince1970,
            accuracy: 0.001
        )
        await source.close()
        await destination.close()
    }

    func testImportCountsEmptyHashAndEveryMissingAssetMaterializationFailure() async throws {
        let root = temporaryDirectory("ImportRejectionCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let items = [
            ClipboardItem(type: .text, text: "empty hash", hash: ""),
            ClipboardItem(type: .image, imageFilename: "missing.png", hash: "missing-image"),
            ClipboardItem(
                type: .imageGroup,
                hash: "missing-group",
                assetFilenames: ["missing-0.png"]
            ),
            ClipboardItem(type: .pdf, hash: "missing-payload", payloadFilename: "missing.pdf"),
            ClipboardItem(type: .pdf, hash: "payload-no-extension", payloadFilename: "noextension"),
            ClipboardItem(type: .text, text: "valid", hash: "valid"),
            ClipboardItem(
                type: .text,
                text: "sensitive valid",
                hash: "sensitive-valid",
                isSensitive: true
            )
        ]
        let archive = ClipboardArchive(
            version: 1,
            createdAt: .now,
            mode: .fullUnencrypted,
            items: items,
            assets: ["Payloads/noextension": Data("payload".utf8)]
        )
        let url = root.appending(path: "rejections.clipboardarchive")
        try encodeArchive(archive).write(to: url)

        let report = try await ExportImportService().importArchive(
            from: url,
            storage: storage,
            existingItems: [],
            encryptionMode: .sensitive
        )
        XCTAssertEqual(report.importedCount, 2)
        XCTAssertEqual(report.rejectedCount, 5)
        let history = await storage.loadHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first { $0.hash == "sensitive-valid" }?.isEncrypted, true)
        await storage.close()
    }

    func testConfigurableArchiveLimitsCoverFileAssetAndItemCaps() async throws {
        let root = temporaryDirectory("ArchiveLimitCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let item = ClipboardItem(type: .text, text: "item", hash: "item")
        let plainArchive = ClipboardArchive(
            version: 1,
            createdAt: .now,
            mode: .fullUnencrypted,
            items: [item],
            assets: ["Images/asset.png": Data([1, 2])]
        )
        let plainURL = root.appending(path: "limit.clipboardarchive")
        try encodeArchive(plainArchive).write(to: plainURL)

        await assertThrowsAsync {
            _ = try await ExportImportService(maximumArchiveBytes: 1).importArchive(
                from: plainURL,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }
        await assertThrowsAsync {
            _ = try await ExportImportService(maximumAssetBytes: 1).importArchive(
                from: plainURL,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }
        await assertThrowsAsync {
            _ = try await ExportImportService(maximumItemCount: 0).importArchive(
                from: plainURL,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }

        let encryptedURL = root.appending(path: "limit-encrypted.clipboardarchive")
        try PasswordArchiveCrypto.encrypt(
            encodeArchive(currentArchive(items: [item], assets: [:], collections: [])),
            password: "password"
        ).write(to: encryptedURL)
        await assertThrowsAsync {
            _ = try await ExportImportService(maximumArchiveBytes: 1).importArchiveAtomically(
                from: encryptedURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }
        await assertThrowsAsync {
            _ = try await ExportImportService(maximumItemCount: 0).importArchiveAtomically(
                from: encryptedURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }
        await storage.close()
    }

    func testIntegrityRejectsTamperedAssetAndCollectionHashes() async throws {
        let root = temporaryDirectory("ArchiveIntegrityDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let itemID = UUID()
        let storedImage = await storage.storeImage(Data("image".utf8), id: itemID)
        let imageName = try XCTUnwrap(storedImage)
        let item = ClipboardItem(id: itemID, type: .image, imageFilename: imageName, hash: "image")
        let collection = ClipboardCollection(name: "Collection")
        let source = root.appending(path: "integrity-source.clipboardarchive")
        let service = ExportImportService()
        try await service.exportArchive(
            items: [item],
            storage: storage,
            to: source,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: true,
            collections: [collection]
        )
        let archive = try decodeArchive(at: source)
        let assetTampered = ClipboardArchive(
            version: archive.version,
            createdAt: archive.createdAt,
            mode: archive.mode,
            items: archive.items,
            assets: archive.assets.mapValues { _ in Data("tampered".utf8) },
            collections: archive.collections,
            itemHashes: archive.itemHashes,
            assetHashes: archive.assetHashes,
            collectionHashes: archive.collectionHashes
        )
        let assetURL = root.appending(path: "asset-tampered.clipboardarchive")
        try encodeArchive(assetTampered).write(to: assetURL)
        await assertThrowsAsync {
            _ = try await service.importArchive(
                from: assetURL,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }

        let changedCollection = ClipboardCollection(
            id: collection.id,
            name: "Changed",
            creationDate: collection.creationDate,
            sortOrder: collection.sortOrder
        )
        let collectionTampered = ClipboardArchive(
            version: archive.version,
            createdAt: archive.createdAt,
            mode: archive.mode,
            items: archive.items,
            assets: archive.assets,
            collections: [changedCollection],
            itemHashes: archive.itemHashes,
            assetHashes: archive.assetHashes,
            collectionHashes: archive.collectionHashes
        )
        let collectionURL = root.appending(path: "collection-tampered.clipboardarchive")
        try encodeArchive(collectionTampered).write(to: collectionURL)
        await assertThrowsAsync {
            _ = try await service.importArchive(
                from: collectionURL,
                storage: storage,
                existingItems: [],
                encryptionMode: .off
            )
        }
        await storage.close()
    }

    func testAtomicImportRejectsWrongModeVersionSymlinkAndRollsBackInvalidMaterialization() async throws {
        let root = temporaryDirectory("AtomicImportDeepCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root.appending(path: "storage"), encryptionService: .ephemeral())
        let service = ExportImportService()
        let invalid = ClipboardItem(type: .text, hash: "invalid-structural")
        let invalidURL = root.appending(path: "invalid-encrypted.clipboardarchive")
        try await service.exportArchive(
            items: [invalid],
            storage: storage,
            to: invalidURL,
            mode: .encrypted,
            includeImagesAndDocuments: true,
            password: "password"
        )
        await assertThrowsAsync {
            _ = try await service.importArchiveAtomically(
                from: invalidURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }
        let rolledBackHistory = await storage.loadHistory()
        XCTAssertTrue(rolledBackHistory.isEmpty)

        let valid = ClipboardItem(type: .text, text: "valid", hash: "valid")
        let wrongMode = currentArchive(items: [valid], assets: [:], collections: [])
        let wrongModeArchive = ClipboardArchive(
            version: wrongMode.version,
            createdAt: wrongMode.createdAt,
            mode: .fullUnencrypted,
            items: wrongMode.items,
            assets: wrongMode.assets,
            collections: wrongMode.collections,
            itemHashes: wrongMode.itemHashes,
            assetHashes: wrongMode.assetHashes,
            collectionHashes: wrongMode.collectionHashes
        )
        let wrongModeURL = root.appending(path: "wrong-mode.clipboardarchive")
        try PasswordArchiveCrypto.encrypt(
            encodeArchive(wrongModeArchive),
            password: "password"
        ).write(to: wrongModeURL)
        await assertThrowsAsync {
            _ = try await service.importArchiveAtomically(
                from: wrongModeURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }

        let wrongVersion = ClipboardArchive(
            version: 1,
            createdAt: .now,
            mode: .encrypted,
            items: [],
            assets: [:]
        )
        let wrongVersionURL = root.appending(path: "wrong-version.clipboardarchive")
        try PasswordArchiveCrypto.encrypt(
            encodeArchive(wrongVersion),
            password: "password"
        ).write(to: wrongVersionURL)
        await assertThrowsAsync {
            _ = try await service.importArchiveAtomically(
                from: wrongVersionURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }

        let link = root.appending(path: "archive-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: invalidURL)
        await assertThrowsAsync {
            _ = try await service.importArchiveAtomically(
                from: link,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }

        let invalidCollection = currentArchive(
            items: [],
            assets: [:],
            collections: [.init(name: "  ")]
        )
        let invalidCollectionURL = root.appending(path: "invalid-collection.clipboardarchive")
        try PasswordArchiveCrypto.encrypt(
            encodeArchive(invalidCollection),
            password: "password"
        ).write(to: invalidCollectionURL)
        await assertThrowsAsync {
            _ = try await service.importArchiveAtomically(
                from: invalidCollectionURL,
                password: "password",
                storage: storage,
                encryptionMode: .all
            )
        }
        await storage.close()
    }

    private func currentArchive(
        items: [ClipboardItem],
        assets: [String: Data],
        collections: [ClipboardCollection]
    ) -> ClipboardArchive {
        ClipboardArchive(
            version: ClipboardArchive.currentVersion,
            createdAt: .now,
            mode: .encrypted,
            items: items,
            assets: assets,
            collections: collections,
            itemHashes: Dictionary(
                uniqueKeysWithValues: items.map {
                    ($0.id.uuidString.lowercased(), checksum($0))
                }
            ),
            assetHashes: assets.mapValues(HashUtility.sha256),
            collectionHashes: Dictionary(
                uniqueKeysWithValues: collections.map {
                    ($0.id.uuidString.lowercased(), checksum($0))
                }
            )
        )
    }

    private func checksum<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return HashUtility.sha256(data: try! encoder.encode(value))
    }

    private func decodeArchive(at url: URL) throws -> ClipboardArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(ClipboardArchive.self, from: Data(contentsOf: url))
    }

    private func encodeArchive(_ archive: ClipboardArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(archive)
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
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
