import Foundation
import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class NoteControllerTests: XCTestCase {
    func testBlankNewDraftIsNotPersisted() async throws {
        let context = makeContext()
        context.controller.openQuickEditor()

        let outcome = await context.controller.flushPendingSave()

        XCTAssertEqual(outcome, .nothingToSave)
        let notes = try await context.storage.loadNotesThrowing()
        XCTAssertEqual(notes, [])
    }

    func testDebounceKeepsOnlyNewestGeneration() async throws {
        let context = makeContext(debounceDuration: .milliseconds(20))
        context.controller.openQuickEditor()
        context.controller.draftBody = "old"
        context.controller.draftBody = "latest"

        try await Task.sleep(for: .milliseconds(80))

        let notes = try await context.storage.loadNotesThrowing()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "latest")
    }

    func testForceSaveSortingSearchAndExistingEmptyNote() async throws {
        let context = makeContext()
        let older = Note(
            title: "Alpha",
            body: "First searchable body",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let newer = Note(
            title: "Beta",
            body: "Second body",
            createdAt: Date(timeIntervalSince1970: 3),
            updatedAt: Date(timeIntervalSince1970: 4)
        )
        try await context.storage.upsertNotesBatchThrowing([older, newer])

        await context.controller.loadIfNeeded()
        XCTAssertEqual(context.controller.notes.map(\.id), [newer.id, older.id])
        context.controller.searchText = "searchable"
        XCTAssertEqual(context.controller.filteredNotes.map(\.id), [older.id])

        context.controller.openEditor(for: older)
        context.controller.draftTitle = ""
        context.controller.draftBody = ""
        let outcome = await context.controller.flushPendingSave()

        XCTAssertEqual(outcome, .saved)
        let stored = try await context.storage.loadNotesThrowing().first { $0.id == older.id }
        XCTAssertEqual(stored?.title, nil)
        XCTAssertEqual(stored?.body, "")
    }

    func testValidationAndStorageFailurePreserveDraft() async throws {
        let context = makeContext(
            operationFailureInjector: { operation in
                if case let .prepareSQL(sql) = operation, sql.contains("INSERT OR REPLACE INTO Notes") {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        )
        context.controller.openQuickEditor()
        context.controller.draftTitle = String(repeating: "a", count: 201)
        context.controller.draftBody = "retained body"

        let invalidOutcome = await context.controller.flushPendingSave()
        XCTAssertEqual(invalidOutcome, .failed)
        XCTAssertEqual(context.controller.saveState, .failed)
        XCTAssertEqual(context.controller.draftBody, "retained body")

        context.controller.draftTitle = "Valid"
        let storageOutcome = await context.controller.flushPendingSave()
        XCTAssertEqual(storageOutcome, .failed)
        XCTAssertEqual(context.controller.saveState, .failed)
        XCTAssertEqual(context.controller.draftTitle, "Valid")
        XCTAssertNotNil(context.controller.errorMessage)
    }

    func testAppModelShutdownFlushesPendingNoteBeforeClosingSQLite() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "NoteTerminationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaultsName = "NoteTerminationDefaults-\(UUID().uuidString)"
        let noteEncryption = try EncryptionService(keyData: Data(repeating: 0x6A, count: 32))
        let storage = StorageService(
            baseDirectory: directory,
            noteEncryptionService: noteEncryption
        )
        let pasteboard = NSPasteboard(name: .init(defaultsName))
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: UserDefaults(suiteName: defaultsName) ?? .standard),
            startsAutomatically: false
        )
        appModel.showQuickNote()
        appModel.notes.draftBody = "Saved during termination"

        let didShutdown = await appModel.shutdown()
        XCTAssertTrue(didShutdown)

        let reopened = StorageService(
            baseDirectory: directory,
            noteEncryptionService: noteEncryption
        )
        let notes = try await reopened.loadNotesThrowing()
        XCTAssertEqual(notes.first?.body, "Saved during termination")
        await reopened.close()
        UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: directory)
    }

    func testConcurrentFlushesPersistNewestRevisionWithoutStaleSavedState() async throws {
        let context = makeContext(debounceDuration: .milliseconds(5))
        context.controller.openQuickEditor()
        context.controller.draftBody = "first revision"

        let firstFlush = Task { await context.controller.flushPendingSave() }
        await Task.yield()
        context.controller.draftBody = "newest revision"
        let secondFlush = Task { await context.controller.flushPendingSave() }

        let firstOutcome = await firstFlush.value
        let secondOutcome = await secondFlush.value
        XCTAssertNotEqual(firstOutcome, .failed)
        XCTAssertNotEqual(secondOutcome, .failed)
        let notes = try await context.storage.loadNotesThrowing()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "newest revision")
        XCTAssertEqual(context.controller.saveState, .saved)
        XCTAssertFalse(context.controller.hasPendingChanges)
    }

    func testFailedSaveBlocksNavigationThenRetryAndDiscardPreserveExpectedDraft() async throws {
        let failure = NoteSaveFailureSwitch()
        failure.shouldFail = true
        let context = makeContext(operationFailureInjector: failure.inject)
        context.controller.openQuickEditor()
        context.controller.draftBody = "must survive"

        context.controller.requestShowList()
        await waitUntil { context.controller.saveState == .failed }
        XCTAssertEqual(context.controller.screen, .editor)
        XCTAssertEqual(context.controller.draftBody, "must survive")

        failure.shouldFail = false
        context.controller.retrySave()
        await waitUntil { context.controller.saveState == .saved }
        context.controller.requestShowList()
        await waitUntil { context.controller.screen == .list }

        let stored = try await context.storage.loadNotesThrowing()
        XCTAssertEqual(stored.first?.body, "must survive")

        let note = try XCTUnwrap(stored.first)
        context.controller.openEditor(for: note)
        context.controller.draftBody = "discard this edit"
        context.controller.errorMessage = "Forced visible failure"
        context.controller.saveState = .failed
        context.controller.discardChanges()
        XCTAssertEqual(context.controller.draftBody, "must survive")
        XCTAssertFalse(context.controller.hasPendingChanges)
    }

    func testFailedQuitFlushKeepsDraftAndStorageOpenUntilRetrySucceeds() async throws {
        let failure = NoteSaveFailureSwitch()
        failure.shouldFail = true
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "NoteFailedTerminationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suite = "NoteFailedTerminationDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let noteEncryption = try EncryptionService(keyData: Data(repeating: 0x7C, count: 32))
        let storage = StorageService(
            baseDirectory: directory,
            noteEncryptionService: noteEncryption,
            operationFailureInjector: failure.inject
        )
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let appModel = AppModel(
            storage: storage,
            settings: AppSettings(defaults: defaults),
            inputEventTapCoordinator: coordinator,
            startsAutomatically: false
        )
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        appModel.showQuickNote()
        appModel.notes.draftBody = "quit-safe draft"

        let firstShutdown = await appModel.shutdown()
        XCTAssertFalse(firstShutdown)
        XCTAssertEqual(appModel.notes.draftBody, "quit-safe draft")
        XCTAssertEqual(appModel.notes.saveState, .failed)
        _ = try await storage.loadNotesThrowing()

        failure.shouldFail = false
        let secondShutdown = await appModel.shutdown()
        XCTAssertTrue(secondShutdown)
        let reopened = StorageService(
            baseDirectory: directory,
            noteEncryptionService: noteEncryption
        )
        let reopenedNotes = try await reopened.loadNotesThrowing()
        XCTAssertEqual(reopenedNotes.first?.body, "quit-safe draft")
        await reopened.close()
    }

    func testBodyLimitFailureKeepsFullDraftVisible() async {
        let context = makeContext()
        let oversizedBody = String(repeating: "a", count: Note.maximumBodyBytes + 1)
        context.controller.openQuickEditor()
        context.controller.draftBody = oversizedBody

        let outcome = await context.controller.flushPendingSave()
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(context.controller.draftBody, oversizedBody)
        XCTAssertNotNil(context.controller.errorMessage)
    }

    private func makeContext(
        debounceDuration: Duration = .milliseconds(400),
        operationFailureInjector: (@Sendable (StorageOperation) throws -> Void)? = nil
    ) -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "NoteControllerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let storage = StorageService(
            baseDirectory: directory,
            operationFailureInjector: operationFailureInjector
        )
        addTeardownBlock {
            await storage.close()
            try? FileManager.default.removeItem(at: directory)
        }
        return Context(
            directory: directory,
            storage: storage,
            controller: NoteController(storage: storage, debounceDuration: debounceDuration)
        )
    }

    private struct Context {
        let directory: URL
        let storage: StorageService
        let controller: NoteController

    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

private final class NoteSaveFailureSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var shouldFail: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }

    func inject(_ operation: StorageOperation) throws {
        guard shouldFail,
              case let .prepareSQL(sql) = operation,
              sql.contains("INSERT OR REPLACE INTO Notes") else { return }
        throw CocoaError(.fileWriteUnknown)
    }
}
