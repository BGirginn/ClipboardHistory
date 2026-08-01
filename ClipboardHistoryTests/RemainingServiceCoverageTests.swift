import AppKit
import Foundation
import XCTest

@testable import ClipboardHistory

@MainActor
final class RemainingServiceCoverageTests: XCTestCase {
    func testClipboardWriterCoversDirectBinaryContentAndLegacyPayloadFallbacks() async throws {
        let root = temporaryDirectory("ClipboardWriterCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("ClipboardWriterCoverage-\(UUID().uuidString)"))
        let writer = ClipboardPasteboardWriter(pasteboard: pasteboard)
        let png = try makeCoveragePNG()
        let pdf = Data("%PDF-1.7\nwriter".utf8)
        let file = root.appending(path: "file.txt")
        try Data("file".utf8).write(to: file)

        let wroteImage = await writer.write(
            content: .images(pngData: [png], hash: "image", sourceBundleIdentifier: nil),
            representation: .original
        )
        XCTAssertTrue(wroteImage)
        let wrotePDF = await writer.write(
            content: .pdf(data: pdf, hash: "pdf", sourceBundleIdentifier: nil),
            representation: .original
        )
        XCTAssertTrue(wrotePDF)
        let wroteFiles = await writer.write(
            content: .files(
                urls: [file],
                bookmarks: [],
                hash: "files",
                sourceBundleIdentifier: nil
            ),
            representation: .original
        )
        XCTAssertTrue(wroteFiles)

        let metadataItem = ClipboardItem(
            type: .text,
            text: "original",
            hash: "metadata",
            protectedMetadata: .init(extractedText: "extracted")
        )
        let wroteMetadata = await writer.write(
            item: metadataItem,
            storage: storage,
            representation: .plainText
        )
        XCTAssertTrue(wroteMetadata)
        XCTAssertEqual(pasteboard.string(forType: .string), "extracted")

        let richID = UUID()
        let storedHTML = await storage.storePayload(
            Data("<b>legacy html</b>".utf8),
            id: richID,
            extension: "html",
            encrypt: false
        )
        let htmlName = try XCTUnwrap(storedHTML)
        let htmlItem = ClipboardItem(
            id: richID,
            type: .richText,
            text: "legacy html",
            hash: "legacy-html",
            payloadFilename: htmlName
        )
        let wroteHTML = await writer.write(item: htmlItem, storage: storage, representation: .html)
        XCTAssertTrue(wroteHTML)
        XCTAssertNotNil(pasteboard.data(forType: .html))

        let rtfID = UUID()
        let storedRTF = await storage.storePayload(
            Data("{\\rtf1 legacy}".utf8),
            id: rtfID,
            extension: "rtf",
            encrypt: false
        )
        let rtfName = try XCTUnwrap(storedRTF)
        let rtfItem = ClipboardItem(
            id: rtfID,
            type: .richText,
            text: "legacy rtf",
            hash: "legacy-rtf",
            payloadFilename: rtfName
        )
        let wroteRTF = await writer.write(item: rtfItem, storage: storage, representation: .richText)
        XCTAssertTrue(wroteRTF)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))

        let bookmark = try file.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let bookmarked = ClipboardItem(
            type: .files,
            hash: "bookmark",
            fileURLs: [],
            fileBookmarks: [bookmark]
        )
        let wroteBookmark = await writer.write(
            item: bookmarked,
            storage: storage,
            representation: .original
        )
        XCTAssertTrue(wroteBookmark)
        XCTAssertEqual(writer.changeCount, pasteboard.changeCount)
        await storage.close()
    }

    func testLocalMigrationFileSystemAndSystemPanelMonitorBoundaries() throws {
        let root = temporaryDirectory("MigrationFileSystemCoverage")
        let source = root.appending(path: "source")
        let destination = root.appending(path: "destination")
        let directory = root.appending(path: "directory", directoryHint: .isDirectory)
        let link = root.appending(path: "link")
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSystem = LocalMigrationFileSystem()
        try fileSystem.createDirectory(at: directory)
        try Data("move".utf8).write(to: source)
        try fileSystem.moveItem(at: source, to: destination)
        XCTAssertTrue(fileSystem.fileExists(at: destination))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        XCTAssertTrue(try fileSystem.isSymbolicLink(at: link))
        try fileSystem.removeItem(at: destination)
        XCTAssertFalse(fileSystem.fileExists(at: destination))

        let monitor = SystemPanelEventMonitor()
        let local = monitor.addLocalMonitor { $0 }
        let global = monitor.addGlobalMonitor { _ in }
        if let local { monitor.removeMonitor(local) }
        if let global { monitor.removeMonitor(global) }
    }

    func testSecretEmptyInputAndTextThumbnailHaveNoOutput() async throws {
        let detection = SecretDetectionService().detect(in: "", sourceBundleIdentifier: nil)
        XCTAssertFalse(detection.isSensitive)
        XCTAssertEqual(detection.confidence, 0)
        XCTAssertTrue(detection.signals.isEmpty)

        let root = temporaryDirectory("TextThumbnailCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let service = ThumbnailService()
        let text = ClipboardItem(type: .text, text: "text", hash: "text-thumbnail")
        let thumbnail = await service.thumbnailData(for: text, storage: storage)
        XCTAssertNil(thumbnail)

        let png = try makeCoveragePNG()
        let imageID = UUID()
        let filename = await storage.storeImage(png, id: imageID)
        let failingCreator = ThumbnailService(imageThumbnailCreator: { _, _, _ in nil })
        let failedThumbnail = await failingCreator.thumbnailData(
            for: ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: filename,
                hash: "forced-thumbnail-failure"
            ),
            storage: storage
        )
        XCTAssertNil(failedThumbnail)
        await storage.close()
    }

    func testAccessibilityTrustChecksUseInjectedEvaluatorsWithoutSystemPrompts() {
        var promptedOptions: CFDictionary?
        let trusted = SystemAccessibilityPasteBackend(
            promptedTrustEvaluator: { options in
                promptedOptions = options
                return true
            },
            trustEvaluator: { false }
        )

        XCTAssertTrue(trusted.isTrusted(prompt: true))
        XCTAssertNotNil(promptedOptions)
        XCTAssertFalse(trusted.isTrusted(prompt: false))
    }

    func testLoggerSubsystemIsAvailable() {
        XCTAssertFalse(AppLog.subsystem.isEmpty)
    }

    func testApplicationDelegateNormalLaunchAndTerminationUseInjectedFactories() async {
        let root = temporaryDirectory("ApplicationDelegateCoverage")
        let suite = "ApplicationDelegateCoverage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let settings = AppSettings(defaults: defaults)
        settings.globalShortcutEnabled = false
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("ApplicationDelegateCoverage-\(UUID().uuidString)"))
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: settings,
            startsAutomatically: false
        )
        var viewModelFactoryCount = 0
        var controllerFactoryCount = 0
        let delegate = ClipboardHistoryAppDelegate(
            environment: [:],
            viewModelFactory: {
                viewModelFactoryCount += 1
                return viewModel
            },
            menuBarControllerFactory: { providedViewModel in
                controllerFactoryCount += 1
                XCTAssertTrue(providedViewModel === viewModel)
                return MenuBarController(
                    viewModel: providedViewModel,
                    panelEventMonitor: ApplicationDelegatePanelEventMonitorStub()
                )
            }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        XCTAssertEqual(viewModelFactoryCount, 1)
        XCTAssertEqual(controllerFactoryCount, 1)
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        await storage.close()
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func makeCoveragePNG() throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 8,
                bitsPerPixel: 32
            )
        )
        bitmap.setColor(.systemPurple, atX: 0, y: 0)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ApplicationDelegatePanelEventMonitorStub: PanelEventMonitoring {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { nil }
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    func removeMonitor(_ monitor: Any) {}
}
