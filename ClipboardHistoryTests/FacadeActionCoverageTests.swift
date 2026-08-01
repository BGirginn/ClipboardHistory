import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import ClipboardHistory

@MainActor
final class FacadeActionCoverageTests: XCTestCase {
    func testSelectionSearchPreviewRestorePasteAndDeleteCommands() async throws {
        let context = makeContext()
        await context.viewModel.insert(.text(value: "first", hash: "first"))
        await context.viewModel.insert(.text(value: "second", hash: "second"))
        let first = try XCTUnwrap(context.viewModel.items.first { $0.hash == "first" })
        let second = try XCTUnwrap(context.viewModel.items.first { $0.hash == "second" })

        context.viewModel.selectedItemID = nil
        context.viewModel.selectNext()
        XCTAssertNotNil(context.viewModel.selectedItemID)
        context.viewModel.selectPrevious()
        context.viewModel.selectOnly(first)
        XCTAssertEqual(context.viewModel.selectedItemIDs, [first.id])
        context.viewModel.toggleSelection(first)
        XCTAssertFalse(context.viewModel.selectedItemIDs.contains(first.id))
        context.viewModel.toggleSelection(second)
        XCTAssertTrue(context.viewModel.selectedItemIDs.contains(second.id))

        var previewed: ClipboardItem?
        context.viewModel.requestPreview = { previewed = $0 }
        context.viewModel.previewSelected()
        XCTAssertNil(previewed)
        let previewable = ClipboardItem(
            type: .files,
            hash: "preview",
            contentSubtype: .file,
            fileURLs: [context.directory.appending(path: "preview.txt").path]
        )
        context.viewModel.items.append(previewable)
        context.viewModel.refreshDisplayedItems()
        context.viewModel.selectOnly(previewable)
        context.viewModel.previewSelected()
        XCTAssertEqual(previewed?.id, previewable.id)

        context.viewModel.searchText = "query"
        context.viewModel.closeOrClearSearch()
        XCTAssertEqual(context.viewModel.searchText, "")
        var closeCount = 0
        context.viewModel.requestClosePanel = { closeCount += 1 }
        context.viewModel.closeOrClearSearch()
        XCTAssertEqual(closeCount, 1)
        let originalFocusRequest = context.viewModel.searchFocusRequest
        context.viewModel.focusSearch()
        XCTAssertEqual(context.viewModel.searchFocusRequest, originalFocusRequest + 1)
        context.viewModel.ignoreNextCopy()

        context.viewModel.selectOnly(first)
        context.viewModel.restoreSelected()
        await waitUntil("restore selected") {
            context.pasteboard.string(forType: .string) == "first"
        }
        context.viewModel.restoreVisibleItem(at: -1)
        context.viewModel.restoreVisibleItem(at: 0)
        await drainTasks()
        context.viewModel.selectOnly(first)
        context.viewModel.pasteSelectedToActiveApp()
        await waitUntil("paste selected") { context.pasteService.pasteCount == 1 }
        context.viewModel.capturePasteTargetApplication()
        XCTAssertEqual(context.pasteService.captureCount, 1)

        context.viewModel.copy(first, as: .plainText)
        context.viewModel.paste(first)
        context.viewModel.restore(first)
        await waitUntil("paste wrapper") { context.pasteService.pasteCount >= 2 }
        await context.viewModel.restoreStoredImage(filename: "missing.png", hash: "missing")

        context.viewModel.showDetails(first)
        XCTAssertEqual(context.viewModel.detailItem?.id, first.id)
        var menuCommandCount = 0
        context.viewModel.menuCommandDidRun = { menuCommandCount += 1 }
        context.viewModel.notifyMenuCommandDidRun()
        XCTAssertEqual(menuCommandCount, 1)
        context.viewModel.clearHistory()
        XCTAssertTrue(context.viewModel.isShowingClearConfirmation)

        context.viewModel.selectOnly(first)
        context.viewModel.deleteSelected()
        await waitUntil("delete selected") {
            !context.viewModel.items.contains(where: { $0.id == first.id })
        }
        context.viewModel.selectedItemIDs = [second.id, previewable.id]
        context.viewModel.deleteSelected()
        await waitUntil("delete multiple") { context.viewModel.items.isEmpty }
        context.viewModel.deleteSelectedItems()
        await cleanup(context)
    }

    func testEditingCollectionAgeCleanupPasteStackAndClearCommands() async throws {
        let context = makeContext()
        let old = ClipboardItem(
            type: .text,
            text: "old",
            creationDate: .now.addingTimeInterval(-7_200),
            hash: "old"
        )
        let current = ClipboardItem(type: .text, text: "current", hash: "current")
        try await context.storage.upsertThrowing(old)
        try await context.storage.upsertThrowing(current)
        context.viewModel.items = [current, old]
        context.viewModel.refreshDisplayedItems()

        context.viewModel.selectOnly(old)
        context.viewModel.toggleSelection(old)
        context.viewModel.toggleSelection(old)
        context.viewModel.updateItem(
            ClipboardItem(type: .text, text: "absent", hash: "absent"),
            title: "ignored",
            editedText: nil,
            tags: "",
            collectionID: nil,
            isSnippet: false
        )
        context.viewModel.move(current, to: UUID())
        context.viewModel.toggleSnippet(current)
        await context.viewModel.drainPendingItemWrites()

        context.viewModel.createCollection(named: "   ")
        context.viewModel.createCollection(named: "Work")
        await waitUntil { context.viewModel.collections.count == 1 }
        context.viewModel.createCollection(named: "work")
        XCTAssertEqual(context.viewModel.collections.count, 1)
        let collection = try XCTUnwrap(context.viewModel.collections.first)
        context.viewModel.deleteCollection(collection)
        await waitUntil { context.viewModel.collections.isEmpty }

        context.viewModel.confirmAgeCleanup()
        context.viewModel.requestAgeCleanup(olderThan: 3_600)
        XCTAssertTrue(context.viewModel.isShowingAgeCleanupConfirmation)
        context.viewModel.confirmAgeCleanup()
        await waitUntil { !context.viewModel.items.contains(where: { $0.id == old.id }) }

        context.viewModel.addToPasteStack(
            ClipboardItem(type: .text, text: "absent", hash: "not-in-history")
        )
        context.viewModel.addToPasteStack(current)
        XCTAssertEqual(context.viewModel.pasteStackItemIDs, [current.id])
        context.viewModel.removeFromPasteStack(current)
        XCTAssertTrue(context.viewModel.pasteStackItemIDs.isEmpty)
        context.viewModel.addToPasteStack(current)
        context.viewModel.settings.pasteStackOrder = .fifo
        context.viewModel.pasteNextStackItem()
        await waitUntil { context.pasteService.pasteCount == 1 }
        context.viewModel.resetPasteStack()

        context.viewModel.confirmClearHistory()
        await waitUntil { context.viewModel.items.isEmpty }
        let persistedHistory = await context.storage.loadHistory()
        XCTAssertTrue(persistedHistory.isEmpty)
        await cleanup(context)
    }

    func testPrivacyTimersSettingsLockSensitiveAndMaintenanceCommands() async throws {
        let clock = RecordingSleepClock()
        let context = makeContext(clock: clock)
        var privacyChanges: [Bool] = []
        context.viewModel.privateModeDidChange = { privacyChanges.append($0) }

        context.viewModel.setPrivateModeEnabled(false)
        context.viewModel.togglePrivateMode()
        XCTAssertTrue(context.viewModel.isPrivateMode)
        context.viewModel.resumeRecording()
        context.viewModel.enablePrivateMode(minutes: 2)
        await waitUntil { !context.viewModel.isPrivateMode }
        context.viewModel.pauseRecording(minutes: 3)
        await waitUntil { context.viewModel.pauseUntil == nil }
        XCTAssertTrue(privacyChanges.contains(true))
        XCTAssertTrue(privacyChanges.contains(false))

        await context.viewModel.insert(.text(value: "migrate", hash: "migrate"))
        context.settings.encryptionMode = .all
        context.viewModel.settingsDidChange()
        if let maintenanceTask = context.viewModel.maintenanceTask {
            await maintenanceTask.value
        }
        XCTAssertEqual(context.viewModel.appliedEncryptionMode, .all)
        context.viewModel.isShuttingDown = true
        context.viewModel.settingsDidChange()
        context.viewModel.isShuttingDown = false

        context.viewModel.setLaunchAtLogin(true)
        await context.viewModel.refreshStorageInformation()
        context.viewModel.dismissError()
        context.viewModel.setGlobalShortcutError("shortcut")
        XCTAssertEqual(context.viewModel.globalShortcutError, "shortcut")

        context.viewModel.setApplicationLockEnabled(true)
        await waitUntil { context.settings.applicationLockEnabled }
        context.viewModel.lock()
        XCTAssertTrue(context.viewModel.isLocked)
        context.viewModel.unlock()
        await waitUntil { !context.viewModel.isLocked }
        context.viewModel.setApplicationLockEnabled(false)
        await waitUntil { !context.settings.applicationLockEnabled }

        context.settings.sensitiveStoragePolicy = .ask
        let firstSecret = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"
        await context.viewModel.insert(.text(value: firstSecret, hash: "secret-one"))
        XCTAssertTrue(context.viewModel.isShowingSensitiveSaveConfirmation)
        context.viewModel.confirmSensitiveSave()
        await waitUntil {
            context.viewModel.items.contains { $0.hash == "secret-one" && $0.isEncrypted }
        }
        let secondSecret = "github_token=ghp_abcdefghijklmnopqrstuvwxyz123456"
        await context.viewModel.insert(.text(value: secondSecret, hash: "secret-two"))
        context.viewModel.keepSensitiveTemporarily()
        XCTAssertFalse(context.viewModel.isShowingSensitiveSaveConfirmation)

        context.settings.historyLimit = 100
        await context.viewModel.insert(.text(value: "cleanup-one", hash: "cleanup-one"))
        await context.viewModel.insert(.text(value: "cleanup-two", hash: "cleanup-two"))
        context.settings.historyLimit = 1
        await context.viewModel.runRetentionCleanup()
        XCTAssertNotNil(context.viewModel.cleanupMessage)
        await cleanup(context)
    }

    func testArchiveAndImageExportTaskWrappers() async throws {
        let context = makeContext()
        let archive = context.directory.appending(path: "wrapper.clipboardarchive")
        context.panels.saveDestinations = [archive]
        context.viewModel.items = [ClipboardItem(type: .text, text: "wrapper", hash: "wrapper")]
        context.viewModel.exportArchive(
            mode: .fullUnencrypted,
            includeImagesAndDocuments: false,
            includeFileReferences: false
        )
        await waitUntil { context.viewModel.archiveStatusMessage == "Export completed." }

        context.viewModel.items = []
        context.panels.openSources = [archive]
        context.viewModel.importArchive()
        await waitUntil { context.viewModel.archiveStatusMessage?.contains("Imported") == true }

        context.viewModel.archiveStatusMessage = nil
        context.panels.openSources = [nil]
        context.viewModel.importStorageRecoveryArchive(password: "password")
        await drainTasks()
        XCTAssertNil(context.viewModel.archiveStatusMessage)

        let png = try makePNG()
        let imageID = UUID()
        let storedFilename = await context.storage.storeImage(png, id: imageID)
        let filename = try XCTUnwrap(storedFilename)
        let output = context.directory.appending(path: "wrapper.png")
        context.panels.saveDestinations = [output]
        context.viewModel.exportImage(
            ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: filename,
                hash: "image-wrapper",
                contentSubtype: .image
            ),
            asJPEG: false
        )
        await waitUntil { FileManager.default.fileExists(atPath: output.path) }
        await cleanup(context)
    }

    private struct Context {
        let directory: URL
        let suite: String
        let storage: StorageService
        let settings: AppSettings
        let pasteboard: NSPasteboard
        let pasteService: StubActiveApplicationPasteService
        let panels: FacadeArchivePanelStub
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext(clock: any SleepClock = SystemSleepClock()) -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FacadeActionCoverageTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "FacadeActionCoverageDefaults-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let storage = StorageService(
            baseDirectory: directory.appending(path: "Storage"),
            encryptionService: .ephemeral()
        )
        let pasteboard = NSPasteboard(name: .init("FacadeActionCoverage-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService()
        let panels = FacadeArchivePanelStub()
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            settings: settings,
            launchAtLoginService: LaunchAtLoginService(backend: FacadeLaunchAtLoginBackend()),
            lockService: AppLockService(authenticator: StubSystemAuthenticator { _ in true }),
            archivePanelSelector: panels,
            storageRecoveryImporter: FacadeRecoveryImporter(),
            sleepClock: clock,
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            suite: suite,
            storage: storage,
            settings: settings,
            pasteboard: pasteboard,
            pasteService: pasteService,
            panels: panels,
            viewModel: viewModel
        )
    }

    private func cleanup(_ context: Context) async {
        context.viewModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.suite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func waitUntil(
        _ label: String = "condition",
        _ predicate: @escaping () -> Bool,
        iterations: Int = 200
    ) async {
        for _ in 0..<iterations {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true: \(label)")
    }

    private func drainTasks() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func makePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class FacadeArchivePanelStub: ArchivePanelSelecting {
    var saveDestinations: [URL?] = []
    var openSources: [URL?] = []

    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL? {
        saveDestinations.isEmpty ? nil : saveDestinations.removeFirst()
    }

    func openSource(allowedTypes: [UTType]) async -> URL? {
        openSources.isEmpty ? nil : openSources.removeFirst()
    }
}

@MainActor
private final class FacadeLaunchAtLoginBackend: LaunchAtLoginBackend {
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}

private actor FacadeRecoveryImporter: StorageRecoveryImporting {
    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult {
        StorageRecoveryImportResult(importedItemCount: 0, rollbackBackupURL: nil)
    }
}
