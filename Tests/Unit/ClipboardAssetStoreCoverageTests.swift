import Foundation
import XCTest

@testable import ClipboardHistory

final class ClipboardAssetStoreCoverageTests: XCTestCase {
    func testStoreLoadReplaceEncryptAndRejectUnsafeOrMissingAssets() async throws {
        let directory = temporaryDirectory()
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Data("first".utf8)
        let replacement = Data("replacement".utf8)

        let unsafeStore = await storage.storeFile(
            data: first,
            logicalFilename: "../unsafe",
            directory: storage.imagesDirectory,
            encrypt: false
        )
        XCTAssertFalse(unsafeStore)
        let firstStore = await storage.storeFile(
            data: first,
            logicalFilename: "plain.png",
            directory: storage.imagesDirectory,
            encrypt: false
        )
        XCTAssertTrue(firstStore)
        let replacementStore = await storage.storeFile(
            data: replacement,
            logicalFilename: "plain.png",
            directory: storage.imagesDirectory,
            encrypt: false
        )
        XCTAssertTrue(replacementStore)
        let loadedReplacement = await storage.loadFile(
            filename: "plain.png",
            directory: storage.imagesDirectory,
            isEncrypted: false
        )
        XCTAssertEqual(loadedReplacement, replacement)
        let encryptedStore = await storage.storeFile(
            data: first,
            logicalFilename: "secret.png",
            directory: storage.imagesDirectory,
            encrypt: true
        )
        XCTAssertTrue(encryptedStore)
        let loadedEncrypted = await storage.loadFile(
            filename: "secret.png",
            directory: storage.imagesDirectory,
            isEncrypted: true
        )
        XCTAssertEqual(loadedEncrypted, first)
        let missingPlain = await storage.loadFile(
            filename: "secret.png",
            directory: storage.imagesDirectory,
            isEncrypted: false
        )
        XCTAssertNil(missingPlain)
        let unsafeLoad = await storage.loadFile(
            filename: "../unsafe",
            directory: storage.imagesDirectory,
            isEncrypted: false
        )
        XCTAssertNil(unsafeLoad)
        XCTAssertTrue(
            storage.physicalURL(
                filename: "secret.png",
                directory: storage.imagesDirectory,
                encrypted: true
            ).lastPathComponent.hasSuffix(".enc")
        )
        let unsafeExists = await storage.fileExists(
            logicalFilename: "../unsafe",
            directory: storage.imagesDirectory,
            encrypted: false
        )
        XCTAssertFalse(unsafeExists)
        await storage.close()

        let failing = StorageService(
            baseDirectory: directory.appending(path: "Failing"),
            encryptionService: .ephemeral(),
            operationFailureInjector: { operation in
                if case .storeAsset = operation { throw CocoaError(.fileWriteNoPermission) }
            }
        )
        let failedStore = await failing.storeFile(
            data: first,
            logicalFilename: "blocked.png",
            directory: failing.imagesDirectory,
            encrypt: false
        )
        XCTAssertFalse(failedStore)
        await failing.close()
    }

    func testRewriteAndDeleteCoverImageGroupThumbnailAndPayloadAssets() async throws {
        let directory = temporaryDirectory()
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = Data("image".utf8)
        let group = Data("group".utf8)
        let thumbnail = Data("thumbnail".utf8)
        let payload = Data("payload".utf8)
        for (filename, data, assetDirectory) in [
            ("image.png", image, storage.imagesDirectory),
            ("group.png", group, storage.imagesDirectory),
            ("thumb.png", thumbnail, storage.thumbnailsDirectory),
            ("payload.pdf", payload, storage.payloadsDirectory)
        ] {
            let didStore = await storage.storeFile(
                data: data,
                logicalFilename: filename,
                directory: assetDirectory,
                encrypt: false
            )
            XCTAssertTrue(didStore)
        }
        let item = ClipboardItem(
            type: .imageGroup,
            imageFilename: "image.png",
            hash: "assets",
            thumbnailFilename: "thumb.png",
            contentSubtype: .imageGroup,
            payloadFilename: "payload.pdf",
            assetFilenames: ["group.png"]
        )

        let didRewrite = try await storage.rewriteAssets(for: item, encrypt: true)
        XCTAssertTrue(didRewrite)
        for (filename, assetDirectory) in [
            ("image.png", storage.imagesDirectory),
            ("group.png", storage.imagesDirectory),
            ("thumb.png", storage.thumbnailsDirectory),
            ("payload.pdf", storage.payloadsDirectory)
        ] {
            let exists = await storage.fileExists(
                logicalFilename: filename,
                directory: assetDirectory,
                encrypted: true
            )
            XCTAssertTrue(exists)
        }
        await storage.deletePhysicalAssets(for: item, encrypted: true)
        let encryptedImageExists = await storage.fileExists(
            logicalFilename: "image.png",
            directory: storage.imagesDirectory,
            encrypted: true
        )
        XCTAssertFalse(encryptedImageExists)
        await storage.deleteAssociatedFiles(for: item)
        let payloadExists = await storage.fileExists(
            logicalFilename: "payload.pdf",
            directory: storage.payloadsDirectory,
            encrypted: false
        )
        XCTAssertFalse(payloadExists)

        let missingImage = ClipboardItem(
            type: .image,
            imageFilename: "missing.png",
            hash: "missing-image",
            contentSubtype: .image
        )
        let didRewriteMissingImage = try await storage.rewriteAssets(
            for: missingImage,
            encrypt: true
        )
        XCTAssertFalse(didRewriteMissingImage)
        let missingPayload = ClipboardItem(
            type: .pdf,
            hash: "missing-payload",
            contentSubtype: .pdf,
            payloadFilename: "missing.pdf"
        )
        let didRewriteMissingPayload = try await storage.rewriteAssets(
            for: missingPayload,
            encrypt: true
        )
        XCTAssertFalse(didRewriteMissingPayload)
        await storage.close()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "ClipboardAssetStoreCoverageTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
