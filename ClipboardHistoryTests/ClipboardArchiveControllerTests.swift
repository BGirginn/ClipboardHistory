import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import ClipboardHistory

@MainActor
final class ClipboardArchiveControllerTests: XCTestCase {
    func testImageExportWritesPNGAndJPEGAndReportsConversionFailure() async throws {
        let context = makeContext()
        let png = try makePNG()
        let id = UUID()
        let storedFilename = await context.storage.storeImage(png, id: id)
        let filename = try XCTUnwrap(storedFilename)
        let item = ClipboardItem(
            id: id,
            type: .image,
            imageFilename: filename,
            hash: "image",
            contentSubtype: .image
        )

        let pngDestination = context.directory.appending(path: "export.png")
        context.panels.saveDestinations = [pngDestination]
        await context.viewModel.performImageExport(item, asJPEG: false)
        XCTAssertEqual(try Data(contentsOf: pngDestination), png)
        XCTAssertEqual(context.panels.lastSuggestedName, "Clipboard Image.png")
        XCTAssertEqual(context.panels.lastAllowedTypes, [.png])

        let jpegDestination = context.directory.appending(path: "export.jpg")
        context.panels.saveDestinations = [jpegDestination]
        await context.viewModel.performImageExport(item, asJPEG: true)
        XCTAssertNotNil(NSImage(contentsOf: jpegDestination))
        XCTAssertEqual(context.panels.lastSuggestedName, "Clipboard Image.jpg")
        XCTAssertEqual(context.panels.lastAllowedTypes, [.jpeg])

        let corruptID = UUID()
        let corruptFilename = await context.storage.storeImage(
            Data("not-an-image".utf8),
            id: corruptID
        )
        let corrupt = ClipboardItem(
            id: corruptID,
            type: .image,
            imageFilename: corruptFilename,
            hash: "corrupt",
            contentSubtype: .image
        )
        context.panels.saveDestinations = [context.directory.appending(path: "bad.jpg")]
        await context.viewModel.performImageExport(corrupt, asJPEG: true)
        XCTAssertTrue(context.viewModel.errorMessage?.contains("Image export failed") == true)

        let callsBeforeMissing = context.panels.saveCallCount
        await context.viewModel.performImageExport(
            ClipboardItem(type: .image, hash: "missing", contentSubtype: .image),
            asJPEG: false
        )
        XCTAssertEqual(context.panels.saveCallCount, callsBeforeMissing)
        await cleanup(context)
    }

    func testArchiveExportImportSuccessFailureAndCancellation() async throws {
        let context = makeContext()
        let item = ClipboardItem(type: .text, text: "archived", hash: "archive")
        context.viewModel.items = [item]
        let archive = context.directory.appending(path: "history.clipboardarchive")
        context.panels.saveDestinations = [archive]

        await context.viewModel.performArchiveExport(
            mode: .fullUnencrypted,
            includeImagesAndDocuments: true,
            includeFileReferences: true,
            password: nil
        )
        XCTAssertEqual(context.viewModel.archiveStatusMessage, "Export completed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertEqual(context.panels.lastSuggestedName, "ClipboardHistory.clipboardarchive")

        context.viewModel.items = []
        context.panels.openSources = [archive]
        await context.viewModel.performArchiveImport(password: nil)
        XCTAssertEqual(context.viewModel.items.first?.text, "archived")
        XCTAssertTrue(context.viewModel.archiveStatusMessage?.contains("Imported 1") == true)

        context.panels.saveDestinations = [context.directory.appending(path: "encrypted.data")]
        await context.viewModel.performArchiveExport(
            mode: .encrypted,
            includeImagesAndDocuments: false,
            includeFileReferences: false,
            password: nil
        )
        XCTAssertTrue(context.viewModel.archiveStatusMessage?.contains("Export failed") == true)
        XCTAssertEqual(
            context.panels.lastSuggestedName,
            "ClipboardHistory-Encrypted.clipboardarchive"
        )

        let invalid = context.directory.appending(path: "invalid.data")
        try Data("invalid".utf8).write(to: invalid)
        context.panels.openSources = [invalid]
        await context.viewModel.performArchiveImport(password: nil)
        XCTAssertTrue(context.viewModel.archiveStatusMessage?.contains("Import failed") == true)

        context.viewModel.archiveStatusMessage = nil
        context.panels.saveDestinations = [nil]
        await context.viewModel.performArchiveExport(
            mode: .fullUnencrypted,
            includeImagesAndDocuments: false,
            includeFileReferences: false,
            password: nil
        )
        XCTAssertNil(context.viewModel.archiveStatusMessage)
        context.panels.openSources = [nil]
        await context.viewModel.performArchiveImport(password: nil)
        XCTAssertNil(context.viewModel.archiveStatusMessage)
        await cleanup(context)
    }

    func testStorageRecoverySuccessFailureEmptyPasswordAndCancellation() async {
        let success = makeContext(recoveryResult: .success(3))
        success.panels.openSources = [success.directory.appending(path: "recovery.data")]
        await success.viewModel.performStorageRecoveryImport(password: "password")
        XCTAssertFalse(success.viewModel.isStorageAvailable)
        XCTAssertTrue(success.viewModel.archiveStatusMessage?.contains("Recovered 3") == true)
        await cleanup(success)

        let failure = makeContext(recoveryResult: .failure)
        failure.panels.openSources = [failure.directory.appending(path: "recovery.data")]
        await failure.viewModel.performStorageRecoveryImport(password: "password")
        XCTAssertFalse(failure.viewModel.isStorageAvailable)
        XCTAssertTrue(failure.viewModel.archiveStatusMessage?.contains("Recovery failed") == true)
        await cleanup(failure)

        let empty = makeContext()
        await empty.viewModel.performStorageRecoveryImport(password: "")
        XCTAssertTrue(empty.viewModel.archiveStatusMessage?.contains("password is required") == true)
        empty.viewModel.archiveStatusMessage = nil
        empty.panels.openSources = [nil]
        await empty.viewModel.performStorageRecoveryImport(password: "password")
        XCTAssertNil(empty.viewModel.archiveStatusMessage)
        await cleanup(empty)
    }

    func testSystemRecoveryImporterForwardsToServiceFailClosed() async {
        let importer = SystemStorageRecoveryImporter()
        do {
            _ = try await importer.migrate(
                encryptedArchive: URL(fileURLWithPath: "/does-not-exist"),
                password: "",
                to: URL(fileURLWithPath: "/does-not-matter")
            )
            XCTFail("Expected password validation failure")
        } catch {
            guard case ExportImportError.passwordRequired = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSystemPanelSelectorConfiguresInjectedPanelsAndHandlesCancellation() async throws {
        let destination = URL(fileURLWithPath: "/private/tmp/save.clipboardarchive")
        let source = URL(fileURLWithPath: "/private/tmp/open.clipboardarchive")
        let save = ArchiveSavePanelStub(response: .OK, url: destination)
        let open = ArchiveOpenPanelStub(response: .OK, url: source)
        let selector = SystemArchivePanelSelector(
            makeSavePanel: { save },
            makeOpenPanel: { open }
        )

        let selectedDestination = await selector.saveDestination(
            suggestedName: "History",
            allowedTypes: [.data]
        )
        XCTAssertEqual(selectedDestination, destination)
        XCTAssertTrue(save.canCreateDirectories)
        XCTAssertEqual(save.nameFieldStringValue, "History")
        XCTAssertEqual(save.allowedContentTypes, [.data])
        let selectedSource = await selector.openSource(allowedTypes: [.json])
        XCTAssertEqual(selectedSource, source)
        XCTAssertFalse(open.canChooseDirectories)
        XCTAssertFalse(open.allowsMultipleSelection)
        XCTAssertEqual(open.allowedContentTypes, [.json])

        save.response = .cancel
        open.response = .cancel
        let cancelledDestination = await selector.saveDestination(
            suggestedName: "Cancelled",
            allowedTypes: []
        )
        let cancelledSource = await selector.openSource(allowedTypes: [])
        XCTAssertNil(cancelledDestination)
        XCTAssertNil(cancelledSource)

        _ = SystemArchivePanelSelector(
            makeSavePanel: NSSavePanel.init,
            makeOpenPanel: NSOpenPanel.init
        )

        let forwardingImporter = SystemStorageRecoveryImporter(
            service: ArchiveRecoveryImporterStub(behavior: .success(2))
        )
        let forwarded = try await forwardingImporter.migrate(
            encryptedArchive: source,
            password: "password",
            to: destination
        )
        XCTAssertEqual(forwarded.importedItemCount, 2)

        let context = makeContext()
        XCTAssertThrowsError(
            try context.viewModel.jpegData(from: try makePNG(), encoder: { _ in nil })
        )
        await cleanup(context)
    }

    private struct Context {
        let directory: URL
        let defaultsSuite: String
        let storage: StorageService
        let panels: ArchivePanelSelectorStub
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext(
        recoveryResult: ArchiveRecoveryImporterStub.Behavior = .success(0)
    ) -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardArchiveControllerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaultsSuite = "ClipboardArchiveControllerDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let storage = StorageService(baseDirectory: directory.appending(path: "Storage"))
        let panels = ArchivePanelSelectorStub()
        let pasteboard = NSPasteboard(name: .init("ArchiveController-\(UUID().uuidString)"))
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            archivePanelSelector: panels,
            storageRecoveryImporter: ArchiveRecoveryImporterStub(behavior: recoveryResult),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            defaultsSuite: defaultsSuite,
            storage: storage,
            panels: panels,
            viewModel: viewModel
        )
    }

    private func cleanup(_ context: Context) async {
        context.viewModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func makePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ArchiveSavePanelStub: ArchiveSavePanelPresenting {
    var canCreateDirectories = false
    var nameFieldStringValue = ""
    var allowedContentTypes: [UTType] = []
    var response: NSApplication.ModalResponse
    let url: URL?

    init(response: NSApplication.ModalResponse, url: URL?) {
        self.response = response
        self.url = url
    }

    func begin() async -> NSApplication.ModalResponse { response }
}

@MainActor
private final class ArchiveOpenPanelStub: ArchiveOpenPanelPresenting {
    var canChooseDirectories = true
    var allowsMultipleSelection = true
    var allowedContentTypes: [UTType] = []
    var response: NSApplication.ModalResponse
    let url: URL?

    init(response: NSApplication.ModalResponse, url: URL?) {
        self.response = response
        self.url = url
    }

    func begin() async -> NSApplication.ModalResponse { response }
}

@MainActor
private final class ArchivePanelSelectorStub: ArchivePanelSelecting {
    var saveDestinations: [URL?] = []
    var openSources: [URL?] = []
    private(set) var saveCallCount = 0
    private(set) var lastSuggestedName: String?
    private(set) var lastAllowedTypes: [UTType] = []

    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL? {
        saveCallCount += 1
        lastSuggestedName = suggestedName
        lastAllowedTypes = allowedTypes
        return saveDestinations.isEmpty ? nil : saveDestinations.removeFirst()
    }

    func openSource(allowedTypes: [UTType]) async -> URL? {
        lastAllowedTypes = allowedTypes
        return openSources.isEmpty ? nil : openSources.removeFirst()
    }
}

private actor ArchiveRecoveryImporterStub: StorageRecoveryImporting {
    enum Behavior: Sendable {
        case success(Int)
        case failure
    }

    let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult {
        switch behavior {
        case let .success(count):
            return StorageRecoveryImportResult(
                importedItemCount: count,
                rollbackBackupURL: nil
            )
        case .failure:
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
