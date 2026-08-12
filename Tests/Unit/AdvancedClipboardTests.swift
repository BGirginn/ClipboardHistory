import AppKit
import Foundation
import PDFKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class AdvancedClipboardTests: XCTestCase {
    func testRichTextStoresSanitizedPayloadAndRestoresFallbacks() async throws {
        let context = makeContext()
        defer { cleanup(context) }
        let rtf = try NSAttributedString(string: "Rich fallback").data(
            from: NSRange(location: 0, length: 13),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let unsafeHTML = Data("<b>Rich fallback</b><script>bad()</script>".utf8)
        let safeHTML = try XCTUnwrap(HTMLSanitizer.sanitize(unsafeHTML))
        let content = ClipboardContent.text(
            value: "Rich fallback",
            rtfData: rtf,
            htmlData: safeHTML,
            subtype: .html,
            hash: HashUtility.sha256(data: safeHTML),
            sourceBundleIdentifier: "com.example.editor"
        )

        await context.viewModel.insert(content)
        let item = try XCTUnwrap(context.viewModel.items.first)
        await context.viewModel.restoreAndWait(item)

        XCTAssertEqual(item.type, .richText)
        XCTAssertEqual(context.pasteboard.string(forType: .string), "Rich fallback")
        XCTAssertEqual(context.pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(context.pasteboard.data(forType: .html), safeHTML)
        await context.storage.close()
    }

    func testPDFStorageMetadataAndRestoration() async throws {
        let context = makeContext()
        defer { cleanup(context) }
        let pdfData = try makePDFData()
        await context.viewModel.insert(
            .pdf(data: pdfData, hash: HashUtility.sha256(data: pdfData), sourceBundleIdentifier: nil)
        )
        let item = try XCTUnwrap(context.viewModel.items.first)

        await context.viewModel.restoreAndWait(item)

        XCTAssertEqual(item.type, .pdf)
        XCTAssertEqual(item.pageCount, 1)
        XCTAssertEqual(item.fileSize, Int64(pdfData.count))
        XCTAssertEqual(context.pasteboard.data(forType: .pdf), pdfData)
        await context.storage.close()
    }

    func testFileURLStorageRestorationAndMissingFileSafety() async throws {
        let context = makeContext()
        defer { cleanup(context) }
        let file = context.directory.appending(path: "example.txt")
        try Data("file".utf8).write(to: file)
        let hash = HashUtility.sha256(text: file.path)
        await context.viewModel.insert(
            .files(
                urls: [file],
                bookmarks: [Data([0x00, 0x01, 0x02])],
                hash: hash,
                sourceBundleIdentifier: nil
            )
        )
        let item = try XCTUnwrap(context.viewModel.items.first)

        await context.viewModel.restoreAndWait(item)
        let restored = context.pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(restored?.first?.standardizedFileURL, file.standardizedFileURL)

        try FileManager.default.removeItem(at: file)
        await context.viewModel.restoreAndWait(item)
        XCTAssertEqual(context.viewModel.items.first?.type, .files)
        await context.storage.close()
    }

    func testMultipleImagesAreGroupedAndRestoredInOrder() async throws {
        let context = makeContext()
        defer { cleanup(context) }
        let first = try makePNG(color: .red)
        let second = try makePNG(color: .blue)
        let hash = HashUtility.sha256(orderedData: [first, second])
        await context.viewModel.insert(
            .images(pngData: [first, second], hash: hash, sourceBundleIdentifier: nil)
        )
        let item = try XCTUnwrap(context.viewModel.items.first)

        await context.viewModel.restoreAndWait(item)

        XCTAssertEqual(item.type, .imageGroup)
        XCTAssertEqual(item.assetFilenames.count, 2)
        XCTAssertEqual(context.pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(context.pasteboard.pasteboardItems?[0].data(forType: .png), first)
        XCTAssertEqual(context.pasteboard.pasteboardItems?[1].data(forType: .png), second)
        await context.storage.close()
    }

    func testTextNormalizationAndURLNormalizationOnlyAffectHashInput() {
        XCTAssertEqual(
            TextNormalizer.normalizedForHash("line 1\r\nline 2  \r"),
            "line 1\nline 2\n"
        )
        XCTAssertEqual(
            TextNormalizer.normalizedURLForHash("HTTPS://Example.COM:443/path"),
            "https://example.com/path"
        )
    }

    func testConcurrentThumbnailGenerationCoalescesPersistsAndRegenerates() async throws {
        let directory = temporaryDirectory("ThumbnailTests")
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let data = try makePNG(color: .green, width: 800, height: 600)
        let id = UUID()
        let storedFilename = await storage.storeImage(data, id: id)
        let filename = try XCTUnwrap(storedFilename)
        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFilename: filename,
            hash: HashUtility.sha256(data: data),
            thumbnailFilename: "thumb.png",
            contentSubtype: .image
        )
        let service = ThumbnailService(cacheMegabytes: 8)

        let concurrentResults = await withTaskGroup(
            of: Data?.self,
            returning: [Data?].self
        ) { group in
            for _ in 0..<12 {
                group.addTask {
                    await service.thumbnailData(for: item, storage: storage)
                }
            }
            var results: [Data?] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        let first = try XCTUnwrap(concurrentResults.compactMap { $0 }.first)
        await service.clearCache()
        let second = await service.thumbnailData(for: item, storage: storage)

        XCTAssertEqual(concurrentResults.count, 12)
        XCTAssertTrue(concurrentResults.allSatisfy { $0 == first })
        XCTAssertEqual(first, second)
        XCTAssertLessThan(first.count, data.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.thumbnailsDirectory.appending(path: "thumb.png").path))
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testRetentionPreservesPinnedItemsAndDeletesAssets() async throws {
        let directory = temporaryDirectory("RetentionTests")
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let old = Date.now.addingTimeInterval(-100 * 86_400)
        let pinned = ClipboardItem(
            type: .text,
            text: "pinned",
            creationDate: old,
            hash: "pinned",
            isPinned: true,
            pinnedAt: .now
        )
        let unpinned = ClipboardItem(type: .text, text: "old", creationDate: old, hash: "old")
        await storage.saveHistory([pinned, unpinned])

        let report = await storage.cleanup(
            historyLimit: 100,
            retentionDays: 30,
            imageRetentionDays: 14,
            maximumStorageBytes: 1_000_000
        )
        let loaded = await storage.loadHistory()

        XCTAssertEqual(report.removedItemCount, 1)
        XCTAssertEqual(loaded.map(\.hash), ["pinned"])
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testFullExportImportMergesAndSkipsDuplicates() async throws {
        let sourceDirectory = temporaryDirectory("ExportSource")
        let destinationDirectory = temporaryDirectory("ExportDestination")
        let sourceStorage = StorageService(baseDirectory: sourceDirectory, encryptionService: .ephemeral())
        let destinationStorage = StorageService(baseDirectory: destinationDirectory, encryptionService: .ephemeral())
        let imageData = try makePNG(color: .purple)
        let id = UUID()
        let storedImageName = await sourceStorage.storeImage(imageData, id: id)
        let imageName = try XCTUnwrap(storedImageName)
        let items = [
            ClipboardItem(type: .text, text: "exported", hash: "text-export"),
            ClipboardItem(id: id, type: .image, imageFilename: imageName, hash: "image-export")
        ]
        await sourceStorage.saveHistory(items)
        let archiveURL = sourceDirectory.appending(path: "history.clipboardarchive")
        let service = ExportImportService()
        try await service.exportArchive(
            items: items,
            storage: sourceStorage,
            to: archiveURL,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: true
        )

        let first = try await service.importArchive(
            from: archiveURL,
            storage: destinationStorage,
            existingItems: []
        )
        let existing = await destinationStorage.loadHistory()
        let second = try await service.importArchive(
            from: archiveURL,
            storage: destinationStorage,
            existingItems: existing
        )

        XCTAssertEqual(first.importedCount, 2)
        XCTAssertEqual(second.duplicateCount, 2)
        XCTAssertEqual(existing.count, 2)
        let importedImage = try XCTUnwrap(existing.first { $0.type == .image })
        let importedImageData = await destinationStorage.imageData(filename: importedImage.imageFilename!)
        XCTAssertEqual(importedImageData, imageData)
        await sourceStorage.close()
        await destinationStorage.close()
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: destinationDirectory)
    }

    func testImportRejectsPathTraversal() async throws {
        let directory = temporaryDirectory("UnsafeImport")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let archive = ClipboardArchive(
            version: ClipboardArchive.currentVersion,
            createdAt: .now,
            mode: .fullUnencrypted,
            items: [],
            assets: ["Images/../escape.png": Data([1])]
        )
        let url = directory.appending(path: "unsafe.clipboardarchive")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(archive).write(to: url)

        await XCTAssertThrowsErrorAsync {
            _ = try await ExportImportService().importArchive(
                from: url,
                storage: storage,
                existingItems: []
            )
        }
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testImportRejectsTamperedItemManifest() async throws {
        let directory = temporaryDirectory("TamperedManifest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let item = ClipboardItem(type: .text, text: "protected", hash: "protected")
        let archive = ClipboardArchive(
            version: ClipboardArchive.currentVersion,
            createdAt: .now,
            mode: .fullUnencrypted,
            items: [item],
            assets: [:],
            itemHashes: [item.id.uuidString.lowercased(): "tampered"]
        )
        let url = directory.appending(path: "tampered.clipboardarchive")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(archive).write(to: url)

        await XCTAssertThrowsErrorAsync {
            _ = try await ExportImportService().importArchive(
                from: url,
                storage: storage,
                existingItems: []
            )
        }
        let remainingItems = await storage.loadHistory()
        XCTAssertTrue(remainingItems.isEmpty)
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testImportRejectsSymbolicLinkArchive() async throws {
        let directory = temporaryDirectory("SymlinkArchive")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let target = directory.appending(path: "target.clipboardarchive")
        let link = directory.appending(path: "link.clipboardarchive")
        try Data("not-an-archive".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        await XCTAssertThrowsErrorAsync {
            _ = try await ExportImportService().importArchive(
                from: link,
                storage: storage,
                existingItems: []
            )
        }
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
    }

    private struct Context {
        let directory: URL
        let storage: StorageService
        let viewModel: ClipboardHistoryViewModel
        let defaultsSuite: String
        let pasteboard: NSPasteboard
    }

    private func makeContext() -> Context {
        let directory = temporaryDirectory("AdvancedClipboardTests")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "AdvancedClipboardDefaults-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.closePanelAfterCopying = false
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("AdvancedClipboardPasteboard-\(UUID().uuidString)"))
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: settings,
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            storage: storage,
            viewModel: viewModel,
            defaultsSuite: suite,
            pasteboard: pasteboard
        )
    }

    private func cleanup(_ context: Context) {
        context.viewModel.prepareForShutdown()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func makePNG(
        color: NSColor,
        width: Int = 4,
        height: Int = 4
    ) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        (color.usingColorSpace(.deviceRGB) ?? color).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func makePDFData() throws -> Data {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        return try XCTUnwrap(document.dataRepresentation())
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}
