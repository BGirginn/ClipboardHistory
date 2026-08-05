import Foundation
import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class NoteControllerTests: XCTestCase {
    func testBlankNewDraftIsNotPersisted() async throws {
        let context = makeContext()
        context.controller.openQuickEditor()

        await context.controller.flushPendingSave()

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
        await context.controller.flushPendingSave()

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

        await context.controller.flushPendingSave()
        XCTAssertEqual(context.controller.saveState, .failed)
        XCTAssertEqual(context.controller.draftBody, "retained body")

        context.controller.draftTitle = "Valid"
        await context.controller.flushPendingSave()
        XCTAssertEqual(context.controller.saveState, .failed)
        XCTAssertEqual(context.controller.draftTitle, "Valid")
        XCTAssertNotNil(context.controller.errorMessage)
    }

    func testViewModelShutdownFlushesPendingNoteBeforeClosingSQLite() async throws {
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
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: UserDefaults(suiteName: defaultsName) ?? .standard),
            startsAutomatically: false
        )
        viewModel.showNotesQuickEditor()
        viewModel.noteController.draftBody = "Saved during termination"

        await viewModel.shutdown()

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
}
