import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import ClipboardHistory

#if DEBUG
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

        var closeCount = 0
        context.viewModel.requestClosePanel = { closeCount += 1 }
        context.viewModel.closePanel()
        XCTAssertEqual(closeCount, 1)
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
        await waitUntil("encryption migration") {
            context.viewModel.appliedEncryptionMode == .all
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
        let secondSecret = "github_token=gh" + "p_abcdefghijklmnopqrstuvwxyz123456"
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

    func testRemainingCaptureInteractionPresentationAndMutationBranches() async throws {
        let context = makeContext()
        await context.viewModel.loadHistoryAndStartMonitoring()
        XCTAssertTrue(context.viewModel.hasStarted)
        context.viewModel.startMonitoring()
        context.viewModel.stopMonitoring()
        context.viewModel.stopMonitoring()

        context.settings.secretDetectionEnabled = false
        let insensitive = context.viewModel.sensitivityResult(
            for: .text(value: "ordinary", hash: "ordinary"),
            analysis: .empty
        )
        XCTAssertFalse(insensitive.isSensitive)

        let now = Date.now
        let newest = ClipboardItem(type: .text, text: "newest", creationDate: now, hash: "newest")
        let recent = ClipboardItem(type: .text, text: "recent", creationDate: now, hash: "recent")
        let old = ClipboardItem(
            type: .text,
            text: "old",
            creationDate: now.addingTimeInterval(-7_200),
            hash: "old"
        )
        context.viewModel.items = [newest, recent, old]
        context.settings.duplicateDetectionScope = .newest
        XCTAssertNil(context.viewModel.duplicateItem(hash: "recent"))
        context.settings.duplicateDetectionScope = .lastTen
        XCTAssertEqual(context.viewModel.duplicateItem(hash: "recent")?.id, recent.id)
        context.settings.duplicateDetectionScope = .lastHour
        XCTAssertNil(context.viewModel.duplicateItem(hash: "old"))
        XCTAssertEqual(context.viewModel.duplicateItem(hash: "recent")?.id, recent.id)
        context.settings.duplicateDetectionScope = .fullHistory
        XCTAssertEqual(context.viewModel.duplicateItem(hash: "old")?.id, old.id)
        context.viewModel.associateExistingItem(
            hash: "missing",
            with: ClipboardPasteboardIdentity(changeCount: 1)
        )

        let collection = ClipboardCollection(name: "Coverage", sortOrder: 0)
        let pinnedEarlier = ClipboardItem(
            type: .text,
            text: "pinned earlier",
            hash: "pinned-earlier",
            isPinned: true,
            pinnedAt: now.addingTimeInterval(-10)
        )
        let pinnedLater = ClipboardItem(
            type: .text,
            text: "pinned later",
            hash: "pinned-later",
            isPinned: true,
            pinnedAt: now
        )
        let richText = ClipboardItem(
            type: .richText,
            text: "rich",
            hash: "rich",
            collectionID: collection.id,
            isSnippet: true
        )
        let image = ClipboardItem(type: .image, hash: "image", contentSubtype: .image)
        context.viewModel.collections = [collection]
        context.viewModel.items = [pinnedEarlier, pinnedLater, richText, image]
        for filter in ClipboardFilter.allCases {
            context.settings.selectedFilter = filter
            context.viewModel.refreshDisplayedItems()
        }
        XCTAssertEqual(context.viewModel.collectionName(for: richText), collection.name)
        XCTAssertNil(context.viewModel.collectionName(for: ClipboardItem(type: .text, hash: "none")))
        context.viewModel.items = []
        context.viewModel.refreshDisplayedItems()
        context.viewModel.moveSelection(by: 1)
        XCTAssertNil(context.viewModel.selectedItemID)

        let restorable = ClipboardItem(type: .text, text: "restore", hash: "restore")
        context.viewModel.items = [restorable]
        context.viewModel.refreshDisplayedItems()
        context.pasteService.result = .targetUnavailable
        let targetUnavailable = await context.viewModel.restoreNow(
            restorable,
            representation: .original,
            directPaste: true
        )
        XCTAssertFalse(targetUnavailable)
        XCTAssertTrue(context.viewModel.errorMessage?.contains("no longer available") == true)
        context.pasteService.result = .eventCreationFailed
        let eventCreationFailed = await context.viewModel.restoreNow(
            restorable,
            representation: .original,
            directPaste: true
        )
        XCTAssertFalse(eventCreationFailed)
        XCTAssertTrue(context.viewModel.errorMessage?.contains("keyboard event") == true)

        context.pasteService.result = .pasted
        context.viewModel.selectedItemIDs = [restorable.id]
        let bulkActions = ClipboardBulkActionsView(viewModel: context.viewModel)
        bulkActions.addSelectedToPasteStack()
        XCTAssertEqual(context.viewModel.pasteStackItemIDs, [restorable.id])
        let pasteStack = ClipboardPasteStackView(viewModel: context.viewModel)
        pasteStack.pasteNext()
        await waitUntil { context.viewModel.pasteStackItemIDs.isEmpty }
        context.viewModel.pasteStackItemIDs = [restorable.id]
        pasteStack.reset()
        XCTAssertTrue(context.viewModel.pasteStackItemIDs.isEmpty)
        context.appModel.router.openSettings()
        ClipboardSettingsView(
            viewModel: context.appModel.settingsFeature,
            close: context.appModel.closeSettings
        ).closeSettings()
        XCTAssertEqual(context.appModel.router.activeFeature, .controlCenter)
        let generalSettings = ClipboardSettingsGeneralView(
            viewModel: context.appModel.settingsFeature
        )
        _ = generalSettings.launchAtLoginBinding.wrappedValue
        generalSettings.launchAtLoginBinding.wrappedValue = true
        XCTAssertTrue(context.viewModel.launchAtLoginService.isEnabled)
        let privacySettings = ClipboardSettingsPrivacyView(
            viewModel: context.appModel.settingsFeature
        )
        _ = privacySettings.privateModeBinding.wrappedValue
        privacySettings.privateModeBinding.wrappedValue = true
        XCTAssertTrue(context.viewModel.isPrivateMode)
        privacySettings.privateModeBinding.wrappedValue = false
        let securitySettings = ClipboardSettingsSecurityView(
            viewModel: context.appModel.settingsFeature
        )
        securitySettings.changeApplicationLockSetting()
        await waitUntil { context.viewModel.isApplicationLockEnabled }
        securitySettings.toggleLock()
        XCTAssertTrue(context.viewModel.isLocked)
        securitySettings.toggleLock()
        await waitUntil { !context.viewModel.isLocked }
        securitySettings.changeApplicationLockSetting()
        await waitUntil { !context.viewModel.isApplicationLockEnabled }
        let advancedSettings = ClipboardSettingsAdvancedView(
            viewModel: context.appModel.settingsFeature,
            newCollectionName: "View Actions"
        )
        advancedSettings.addCollection()
        await waitUntil { context.viewModel.collections.contains { $0.name == "View Actions" } }
        let addedCollection = try XCTUnwrap(
            context.viewModel.collections.first { $0.name == "View Actions" }
        )
        ClipboardCollectionSettingsRow(
            viewModel: context.appModel.settingsFeature,
            collection: addedCollection
        ).deleteCollection()
        await waitUntil { !context.viewModel.collections.contains { $0.id == addedCollection.id } }
        context.viewModel.pasteStackItemIDs = [restorable.id]
        advancedSettings.resetPasteStack()
        XCTAssertTrue(context.viewModel.pasteStackItemIDs.isEmpty)
        context.viewModel.selectedItemIDs = [restorable.id]
        bulkActions.deleteSelectedItems()
        await waitUntil { context.viewModel.items.isEmpty }

        context.viewModel.lastProgrammaticallyWrittenHash = "stale"
        context.viewModel.lastProgrammaticallyWrittenIdentity = ClipboardPasteboardIdentity(changeCount: 10)
        await context.viewModel.insert(
            .text(value: "new clipboard", hash: "new-clipboard"),
            pasteboardIdentity: ClipboardPasteboardIdentity(changeCount: 11)
        )
        XCTAssertNil(context.viewModel.lastProgrammaticallyWrittenIdentity)

        try await context.storage.upsertCollection(collection)
        let collected = ClipboardItem(
            type: .text,
            text: "collected",
            hash: "collected",
            collectionID: collection.id
        )
        try await context.storage.upsertThrowing(collected)
        context.viewModel.collections = [collection]
        context.viewModel.items = [collected]
        context.viewModel.detailItem = collected
        context.viewModel.deleteCollection(collection)
        await waitUntil { context.viewModel.collections.isEmpty }
        XCTAssertNil(context.viewModel.detailItem?.collectionID)

        await context.storage.close()
        context.viewModel.createCollection(named: "Cannot Save")
        await waitUntil { context.viewModel.errorMessage == "Collection could not be saved." }
        context.viewModel.collections = [collection]
        context.viewModel.deleteCollection(collection)
        await waitUntil { context.viewModel.errorMessage == "Collection could not be deleted." }
        await cleanup(context)

        let automatic = makeContext(startsAutomatically: true)
        await waitUntil { automatic.viewModel.hasStarted }
        await cleanup(automatic)

        let throwingClock = FacadeThrowingSleepClock()
        let timeout = makeContext(clock: throwingClock)
        timeout.settings.pasteStackTimeoutMinutes = 1
        timeout.viewModel.items = [restorable]
        timeout.viewModel.pasteStackItemIDs = [restorable.id]
        timeout.viewModel.schedulePasteStackTimeout()
        await drainTasks()
        let didSleep = await throwingClock.didSleep
        XCTAssertTrue(didSleep)
        await cleanup(timeout)
    }

    func testContextMenuCommandRoutingRunsEveryActionAfterMenuNotification() {
        let item = ClipboardItem(type: .image, hash: "menu", contentSubtype: .image)
        let collection = ClipboardCollection(name: "Menu", sortOrder: 0)
        var events: [String] = []
        let actions = ClipboardItemActions(
            selectAndCopy: { _ in events.append("select") },
            copy: { _ in events.append("copy") },
            paste: { _ in events.append("paste") },
            copyAs: { _, representation in events.append("copyAs:\(representation.rawValue)") },
            pasteAs: { _, representation in events.append("pasteAs:\(representation.rawValue)") },
            togglePin: { _ in events.append("pin") },
            toggleSnippet: { _ in events.append("snippet") },
            moveToCollection: { _, id in events.append("collection:\(id?.uuidString ?? "none")") },
            collections: [collection],
            addToPasteStack: { _ in events.append("stackAdd") },
            removeFromPasteStack: { _ in events.append("stackRemove") },
            pasteStackItemIDs: [],
            dragProvider: { _ in NSItemProvider() },
            showDetails: { _ in events.append("details") },
            reveal: { _ in events.append("reveal") },
            exportImage: { _, jpeg in events.append(jpeg ? "jpeg" : "png") },
            delete: { _ in events.append("delete") },
            menuCommandDidRun: { events.append("menu") }
        )
        let commands = ClipboardItemMenuCommands(item: item, actions: actions)

        commands.copy()
        commands.paste()
        commands.pasteAsPlainText()
        commands.pasteAs(.html)
        commands.copyAs(.richText)
        commands.togglePin()
        commands.toggleSnippet()
        commands.removeFromCollection()
        commands.move(to: collection.id)
        commands.addToPasteStack()
        commands.removeFromPasteStack()
        commands.showDetails()
        commands.reveal()
        commands.exportPNG()
        commands.exportJPEG()
        commands.deleteItem()
        ClipboardItemRepresentationMenuCommand(
            commands: commands,
            representation: .original,
            operation: .copy
        ).perform()
        ClipboardItemRepresentationMenuCommand(
            commands: commands,
            representation: .original,
            operation: .paste
        ).perform()
        ClipboardItemCollectionMenuCommand(
            commands: commands,
            collectionID: collection.id
        ).perform()

        XCTAssertEqual(events.filter { $0 == "menu" }.count, 19)
        XCTAssertTrue(events.contains("copy"))
        XCTAssertTrue(events.contains("paste"))
        XCTAssertTrue(events.contains("png"))
        XCTAssertTrue(events.contains("jpeg"))
        XCTAssertTrue(events.contains("delete"))
    }

    func testPanelRouterHeaderQuickSelectionAndKeyboardActions() async throws {
        let context = makeContext()
        await context.viewModel.insert(.text(value: "panel", hash: "panel"))
        let item = try XCTUnwrap(context.viewModel.items.first)
        context.settings.duplicateDetectionScope = .newest
        XCTAssertEqual(context.viewModel.duplicateItem(hash: item.hash)?.id, item.id)
        let associatedIdentity = ClipboardPasteboardIdentity(changeCount: 41)
        context.viewModel.associateExistingItem(hash: item.hash, with: associatedIdentity)
        XCTAssertEqual(context.viewModel.pasteboardIdentityByItemID[item.id], associatedIdentity)
        context.viewModel.lastProgrammaticallyWrittenHash = item.hash
        context.viewModel.lastProgrammaticallyWrittenIdentity = associatedIdentity
        await context.viewModel.insert(
            .text(value: "panel", hash: item.hash),
            pasteboardIdentity: associatedIdentity
        )
        XCTAssertNil(context.viewModel.lastProgrammaticallyWrittenIdentity)

        let temporaryItem = ClipboardItem(type: .text, text: "temporary", hash: "temporary")
        context.viewModel.items.insert(temporaryItem, at: 0)
        context.viewModel.temporaryContent[temporaryItem.id] = .text(
            value: "temporary",
            hash: temporaryItem.hash
        )
        let restoredTemporary = await context.viewModel.restoreNow(
            temporaryItem,
            representation: .original,
            directPaste: false
        )
        XCTAssertTrue(restoredTemporary)
        context.settings.selectedSortMode = .recentlyUsed
        XCTAssertNotNil(context.viewModel.markAsUsedImmediately(temporaryItem))
        let selectedRouter = ClipboardPanelItemActionRouter(
            viewModel: context.viewModel,
            commandModifierIsPressed: { true }
        )
        selectedRouter.selectAndCopy(item)
        XCTAssertFalse(context.viewModel.selectedItemIDs.contains(item.id))
        selectedRouter.selectAndCopy(item)
        XCTAssertTrue(context.viewModel.selectedItemIDs.contains(item.id))
        let router = ClipboardPanelItemActionRouter(
            viewModel: context.viewModel,
            commandModifierIsPressed: { false }
        )
        ClipboardPanelItemActionRouter(viewModel: context.viewModel).selectAndCopy(item)
        router.selectAndCopy(item)
        router.copy(item)
        router.paste(item)
        router.copyAs(item, .plainText)
        router.pasteAs(item, .plainText)
        router.togglePin(item)
        router.toggleSnippet(item)
        router.move(item, nil)
        router.addToPasteStack(item)
        router.removeFromPasteStack(item)
        _ = router.dragProvider(item)
        router.showDetails(item)
        router.reveal(ClipboardItem(type: .text, text: "safe", hash: "safe"))
        router.exportImage(ClipboardItem(type: .text, text: "safe", hash: "export-safe"), false)
        var menuCount = 0
        context.viewModel.menuCommandDidRun = { menuCount += 1 }
        router.menuCommandDidRun()
        XCTAssertEqual(menuCount, 1)
        router.delete(ClipboardItem(type: .text, text: "absent", hash: "absent-delete"))
        await drainTasks()

        let rowActions = ClipboardItemActions(
            selectAndCopy: router.selectAndCopy,
            copy: router.copy,
            paste: router.paste,
            copyAs: router.copyAs,
            pasteAs: router.pasteAs,
            togglePin: router.togglePin,
            toggleSnippet: router.toggleSnippet,
            moveToCollection: router.move,
            collections: [],
            addToPasteStack: router.addToPasteStack,
            removeFromPasteStack: router.removeFromPasteStack,
            pasteStackItemIDs: [],
            dragProvider: router.dragProvider,
            showDetails: router.showDetails,
            reveal: router.reveal,
            exportImage: router.exportImage,
            delete: router.delete,
            menuCommandDidRun: router.menuCommandDidRun
        )
        let row = ClipboardItemRow(
            item: item,
            isSelected: true,
            isCopied: false,
            isLocked: false,
            storage: context.storage,
            thumbnailService: .shared,
            actions: rowActions
        )
        row.selectAndCopy()
        row.updateHover(true)
        _ = row.dragProvider()
        _ = row.body

        let encryptedImage = ClipboardItem(
            type: .imageGroup,
            hash: "encrypted-image-row",
            assetFilenames: ["first.png", "second.png"],
            isEncrypted: true
        )
        _ = ImageClipboardItemRow(
            item: encryptedImage,
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: false
        ).body
        _ = DocumentClipboardItemRow(
            item: ClipboardItem(
                type: .files,
                hash: "encrypted-document-row",
                fileURLs: [],
                isEncrypted: true
            ),
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: false
        ).body

        let png = try makePNG()
        let imageID = UUID()
        let storedImageFilename = await context.storage.storeImage(png, id: imageID)
        let imageFilename = try XCTUnwrap(storedImageFilename)
        let imageItem = ClipboardItem(
            id: imageID,
            type: .image,
            imageFilename: imageFilename,
            hash: "preview-image",
            contentSubtype: .image
        )
        await ClipboardFullPreview(item: imageItem, storage: context.storage).loadImage()
        await ClipboardFullPreview(
            item: ClipboardItem(type: .pdf, hash: "preview-pdf", contentSubtype: .pdf),
            storage: context.storage
        ).loadImage()
        await ClipboardFullPreview(
            item: ClipboardItem(type: .image, hash: "preview-without-file", contentSubtype: .image),
            storage: context.storage
        ).loadImage()
        _ = ClipboardFullPreview(
            item: imageItem,
            storage: context.storage,
            image: NSImage(size: NSSize(width: 2, height: 2))
        ).body
        let thumbnail = ClipboardImageThumbnail(
            item: imageItem,
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: false
        )
        await thumbnail.loadThumbnail()
        await ClipboardImageThumbnail(
            item: imageItem,
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: true
        ).loadThumbnail()
        _ = ClipboardImageThumbnail(
            item: imageItem,
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: false,
            image: NSImage(size: NSSize(width: 2, height: 2))
        ).body
        _ = ClipboardImageThumbnail(
            item: imageItem,
            storage: context.storage,
            thumbnailService: .shared,
            isLocked: false,
            didFail: true
        ).body

        let detail = ClipboardDetailView(item: item, viewModel: context.viewModel)
        context.viewModel.detailItem = item
        detail.goBack()
        XCTAssertNil(context.viewModel.detailItem)
        detail.copyItem()
        detail.saveChanges()
        var transformedText = "hello world"
        let transformBinding = Binding(
            get: { transformedText },
            set: { transformedText = $0 }
        )
        ClipboardTextTransformationButton(
            transformation: .uppercase,
            text: transformBinding
        ).apply()
        XCTAssertEqual(transformedText, "HELLO WORLD")
        _ = ClipboardTextTransformationButton(
            transformation: .lowercase,
            text: transformBinding
        ).body

        let menuCommands = ClipboardItemMenuCommands(item: item, actions: rowActions)
        for representation in PasteRepresentation.allCases {
            _ = ClipboardItemRepresentationMenuButton(
                command: ClipboardItemRepresentationMenuCommand(
                    commands: menuCommands,
                    representation: representation,
                    operation: .copy
                )
            ).body
        }
        let collection = ClipboardCollection(name: "Coverage")
        _ = ClipboardItemCollectionMenuButton(
            title: collection.name,
            command: ClipboardItemCollectionMenuCommand(
                commands: menuCommands,
                collectionID: collection.id
            )
        ).body
        _ = ClipboardItemContextMenu(
            item: ClipboardItem(type: .files, hash: "files-menu", fileURLs: ["/tmp/file"]),
            actions: rowActions
        ).body
        _ = ClipboardCollectionSettingsRow(
            viewModel: context.appModel.settingsFeature,
            collection: collection
        ).body
        _ = ClipboardSettingsMessage(message: nil, color: .red).body
        _ = ClipboardSettingsMessage(message: "Text error", color: .red).body
        _ = ClipboardSettingsMessage(
            message: "Label error",
            color: .orange,
            usesLabel: true
        ).body
        _ = ClipboardRecordingStatusView(isPrivateMode: true, pauseUntil: nil).body
        _ = ClipboardRecordingStatusView(
            isPrivateMode: false,
            pauseUntil: .now.addingTimeInterval(60)
        ).body
        _ = ClipboardRecordingStatusView(isPrivateMode: false, pauseUntil: nil).body
        XCTAssertTrue(
            ClipboardSettingsSecurityView(viewModel: context.appModel.settingsFeature)
                .applicationLockAccessibilityLabel("failure")
                .contains("failure")
        )

        let storageSettings = ClipboardSettingsStorageView(
            viewModel: context.appModel.settingsFeature,
            archivePassword: "password",
            includeArchiveAssets: false,
            includeArchiveFileReferences: false
        )
        storageSettings.runCleanup()
        storageSettings.exportMetadata()
        storageSettings.exportEncrypted()
        storageSettings.requestUnencryptedExport()
        storageSettings.exportUnencrypted()
        storageSettings.importArchive()
        storageSettings.cancelDialog()
        ClipboardStorageRecoveryView(
            viewModel: context.appModel.settingsFeature,
            archivePassword: "password"
        ).importArchive()
        await drainTasks()

        ClipboardQuickSelectionButton(viewModel: context.viewModel, index: 0).restore()
        await drainTasks()

        var didOpenSettings = false
        let header = ClipboardPanelHeaderView(
            viewModel: context.viewModel,
            backToHome: {},
            openSettings: { didOpenSettings = true }
        )
        let historyActions = ClipboardHistoryActionsMenu(viewModel: context.viewModel)
        historyActions.requestAgeCleanup(3_600)
        XCTAssertEqual(context.viewModel.pendingAgeCleanupInterval, 3_600)
        historyActions.requestAgeCleanup(86_400)
        XCTAssertEqual(context.viewModel.pendingAgeCleanupInterval, 86_400)
        historyActions.requestAgeCleanup(604_800)
        XCTAssertEqual(context.viewModel.pendingAgeCleanupInterval, 604_800)
        historyActions.requestAgeCleanup(2_592_000)
        XCTAssertEqual(context.viewModel.pendingAgeCleanupInterval, 2_592_000)
        header.openSettings()
        XCTAssertTrue(didOpenSettings)
        context.viewModel.setApplicationLockEnabled(true)
        await waitUntil { context.viewModel.isApplicationLockEnabled }
        let lockControls = ClipboardApplicationLockControls(
            viewModel: context.appModel.settingsFeature
        )
        _ = lockControls.body
        lockControls.toggleLock()
        XCTAssertTrue(context.viewModel.isLocked)
        _ = lockControls.body
        lockControls.toggleLock()
        await waitUntil { !context.viewModel.isLocked }
        historyActions.toggleLock()
        XCTAssertTrue(context.viewModel.isLocked)
        historyActions.toggleLock()
        await waitUntil { !context.viewModel.isLocked }

        let panel = ClipboardPanelView(viewModel: context.viewModel)
        _ = panel.body
        panel.cancelDialog()
        XCTAssertFalse(panel.handleKeyEvent(keyEvent(keyCode: 3, modifiers: .command, characters: "f")))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 53)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 51, modifiers: .command)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 51, modifiers: [.command, .shift])))
        XCTAssertFalse(panel.handleKeyEvent(keyEvent(keyCode: 51, modifiers: .option)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 125)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 126)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 36)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 76)))
        XCTAssertTrue(panel.handleKeyEvent(keyEvent(keyCode: 49)))
        XCTAssertFalse(panel.handleKeyEvent(keyEvent(keyCode: 1)))
        context.appModel.showKeyboardCleaning()
        XCTAssertEqual(context.appModel.router.activeFeature, .keyboardCleaning)
        context.appModel.openSettings()
        XCTAssertEqual(context.appModel.router.activeFeature, .settings)
        context.appModel.closeSettings()
        XCTAssertEqual(context.appModel.router.activeFeature, .keyboardCleaning)
        context.appModel.showClipboard()
        context.viewModel.lockService.lock()
        XCTAssertFalse(panel.handleKeyEvent(keyEvent(keyCode: 125)))

        var scrollActions = 0
        ClipboardHistoryListView.scrollToSelected(reduceMotion: true) { scrollActions += 1 }
        ClipboardHistoryListView.scrollToSelected(reduceMotion: false) { scrollActions += 1 }
        XCTAssertEqual(scrollActions, 2)

        let revealedFile = context.directory.appending(path: "revealed.txt")
        context.viewModel.reveal(
            ClipboardItem(type: .files, hash: "reveal-file", fileURLs: [revealedFile.path])
        )
        context.viewModel.reveal(imageItem)
        XCTAssertEqual(context.workspaceRevealer.urls.count, 2)

        let systemRevealRecorder = FacadeWorkspaceRevealer()
        SystemWorkspaceRevealer(revealAction: systemRevealRecorder.reveal).reveal([revealedFile])
        XCTAssertEqual(systemRevealRecorder.urls, [[revealedFile]])

        let oldItem = ClipboardItem(
            type: .text,
            text: "expired",
            creationDate: .now.addingTimeInterval(-10 * 86_400),
            hash: "expired"
        )
        try await context.storage.upsertThrowing(oldItem)
        context.viewModel.items.append(oldItem)
        context.viewModel.pasteboardIdentityByItemID[oldItem.id] = .init(changeCount: 90)
        context.viewModel.pasteboardIdentityByItemID[item.id] = .init(changeCount: 91)
        context.settings.retentionDays = 1
        await context.viewModel.runRetentionCleanup()
        XCTAssertNil(context.viewModel.pasteboardIdentityByItemID[oldItem.id])
        await cleanup(context)
    }

    func testCaptureAndSensitivePersistenceFailuresRemovePartialAssets() async throws {
        let assetCounter = FacadeLockedCounter()
        let partial = makeContext(operationFailureInjector: { operation in
            guard case .storeAsset = operation else { return }
            if assetCounter.increment() == 2 { throw FacadeInjectedFailure() }
        })
        let png = try makePNG()
        let partialItem = await partial.viewModel.makeItem(
            from: .images(
                pngData: [png, png],
                hash: "partial-image-group",
                sourceBundleIdentifier: nil
            ),
            sensitive: false,
            temporary: false,
            encrypted: false
        )
        XCTAssertNil(partialItem)
        let remainingPartialAssets = try FileManager.default.contentsOfDirectory(
            at: partial.storage.imagesDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingPartialAssets.isEmpty)
        await cleanup(partial)

        let persistence = makeContext(operationFailureInjector: { operation in
            guard case let .prepareSQL(sql) = operation,
                  sql.contains("INSERT OR REPLACE INTO ClipboardItems") else { return }
            throw FacadeInjectedFailure()
        })
        await persistence.viewModel.insertSensitivePermanently(
            .image(pngData: png, hash: "sensitive-persistence-failure")
        )
        XCTAssertTrue(
            persistence.viewModel.errorMessage?.contains("could not be saved securely") == true
        )
        let remainingSensitiveAssets = try FileManager.default.contentsOfDirectory(
            at: persistence.storage.imagesDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingSensitiveAssets.isEmpty)
        await cleanup(persistence)
    }

    private struct Context {
        let directory: URL
        let suite: String
        let storage: StorageService
        let settings: AppSettings
        let pasteboard: NSPasteboard
        let pasteService: StubActiveApplicationPasteService
        let panels: FacadeArchivePanelStub
        let workspaceRevealer: FacadeWorkspaceRevealer
        let appModel: AppModel
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext(
        clock: any SleepClock = SystemSleepClock(),
        startsAutomatically: Bool = false,
        operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)? = nil
    ) -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FacadeActionCoverageTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "FacadeActionCoverageDefaults-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let storage = StorageService(
            baseDirectory: directory.appending(path: "Storage"),
            encryptionService: .ephemeral(),
            operationFailureInjector: operationFailureInjector
        )
        let pasteboard = NSPasteboard(name: .init("FacadeActionCoverage-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService()
        let panels = FacadeArchivePanelStub()
        let workspaceRevealer = FacadeWorkspaceRevealer()
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            settings: settings,
            launchAtLoginService: LaunchAtLoginService(backend: FacadeLaunchAtLoginBackend()),
            lockService: AppLockService(authenticator: StubSystemAuthenticator { _ in true }),
            archivePanelSelector: panels,
            storageRecoveryImporter: FacadeRecoveryImporter(),
            workspaceRevealer: workspaceRevealer,
            sleepClock: clock,
            startsAutomatically: startsAutomatically
        )
        return Context(
            directory: directory,
            suite: suite,
            storage: storage,
            settings: settings,
            pasteboard: pasteboard,
            pasteService: pasteService,
            panels: panels,
            workspaceRevealer: workspaceRevealer,
            appModel: appModel,
            viewModel: appModel.clipboard
        )
    }

    private func cleanup(_ context: Context) async {
        context.appModel.prepareForShutdown()
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

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

private actor FacadeThrowingSleepClock: SleepClock {
    private(set) var didSleep = false

    func sleep(for duration: Duration) async throws {
        didSleep = true
        throw CancellationError()
    }
}

private struct FacadeInjectedFailure: Error {}

private final class FacadeLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
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

@MainActor
private final class FacadeWorkspaceRevealer: WorkspaceRevealing {
    private(set) var urls: [[URL]] = []

    func reveal(_ urls: [URL]) {
        self.urls.append(urls)
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
#endif
