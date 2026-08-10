import Combine
import Foundation

@MainActor
final class NoteController: ObservableObject {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    private struct DraftSnapshot: Sendable {
        let note: Note
        let revision: Int
        let title: String
        let body: String
    }

    private enum SnapshotResult {
        case snapshot(DraftSnapshot)
        case nothingToSave
        case failed
    }

    @Published var notes: [Note] = []
    @Published var searchText = ""
    @Published private(set) var screen: NoteScreen = .list
    @Published var draftTitle = "" {
        didSet { draftDidChange() }
    }
    @Published var draftBody = "" {
        didSet { draftDidChange() }
    }
    @Published private(set) var draftSessionID = UUID()
    @Published var errorMessage: String?
    @Published var saveState: SaveState = .idle
    @Published var isShowingDeleteConfirmation = false
    @Published var isShowingDiscardConfirmation = false

    private let storage: StorageService
    private let debounceDuration: Duration
    private var debounceTask: Task<Void, Never>?
    private var saveTail: Task<NoteFlushOutcome, Never>?
    private var draftRevision = 0
    private var draftID = UUID()
    private var draftCreatedAt = Date.now
    private var isPersistedDraft = false
    private var isConfiguringDraft = false
    private var lastPersistedTitle = ""
    private var lastPersistedBody = ""
    private var hasLoaded = false

    init(storage: StorageService, debounceDuration: Duration = .milliseconds(400)) {
        self.storage = storage
        self.debounceDuration = debounceDuration
    }

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            (note.resolvedTitle ?? "").localizedStandardContains(query)
                || note.body.localizedStandardContains(query)
        }
    }

    var canDeleteDraft: Bool {
        isPersistedDraft
    }

    var hasPendingChanges: Bool {
        if isPersistedDraft {
            return draftTitle != lastPersistedTitle || draftBody != lastPersistedBody
        }
        return draftHasContent
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        do {
            notes = try await storage.loadNotesThrowing()
                .sorted { $0.updatedAt > $1.updatedAt }
            hasLoaded = true
        } catch {
            errorMessage = String(localized: "Notes could not be loaded: \(error.localizedDescription)")
        }
    }

    func reload() async {
        hasLoaded = false
        await loadIfNeeded()
    }

    func openQuickEditor() {
        if saveState == .failed, hasPendingChanges {
            screen = .editor
        } else {
            configureNewDraft()
            screen = .editor
        }
        Task { [weak self] in
            await self?.loadIfNeeded()
        }
    }

    func requestNewNote() {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await flushPendingSave()
            guard outcome.allowsTransition else { return }
            configureNewDraft()
            screen = .editor
        }
    }

    func openEditor(for note: Note) {
        debounceTask?.cancel()
        configureDraft(with: note)
        screen = .editor
    }

    func requestShowList() {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await flushPendingSave()
            guard outcome.allowsTransition else { return }
            showList()
        }
    }

    func showList() {
        screen = .list
    }

    func saveImmediately() {
        Task { [weak self] in
            await self?.flushPendingSave()
        }
    }

    @discardableResult
    func flushPendingSave() async -> NoteFlushOutcome {
        debounceTask?.cancel()
        debounceTask = nil
        _ = await saveTail?.value

        while true {
            let revision = draftRevision
            switch makeSnapshot(revision: revision) {
            case let .snapshot(snapshot):
                let outcome = await enqueue(snapshot).value
                guard outcome != .failed else { return .failed }
                if revision == draftRevision {
                    return .saved
                }
            case .nothingToSave:
                return .nothingToSave
            case .failed:
                return .failed
            }
        }
    }

    func retrySave() {
        saveImmediately()
    }

    func discardChanges() {
        debounceTask?.cancel()
        debounceTask = nil
        isConfiguringDraft = true
        draftRevision += 1
        if isPersistedDraft {
            draftTitle = lastPersistedTitle
            draftBody = lastPersistedBody
            saveState = .saved
        } else {
            draftTitle = ""
            draftBody = ""
            saveState = .idle
        }
        draftSessionID = UUID()
        errorMessage = nil
        isShowingDiscardConfirmation = false
        isConfiguringDraft = false
    }

    func deleteDraft() async {
        debounceTask?.cancel()
        debounceTask = nil
        _ = await saveTail?.value
        guard isPersistedDraft else {
            configureNewDraft()
            showList()
            return
        }
        do {
            try await storage.deleteNoteThrowing(id: draftID)
            notes.removeAll { $0.id == draftID }
            configureNewDraft()
            showList()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Note could not be deleted: \(error.localizedDescription)")
        }
    }

    private func draftDidChange() {
        guard !isConfiguringDraft else { return }
        draftRevision += 1
        validateDraft()
        debounceTask?.cancel()
        let revision = draftRevision
        debounceTask = Task { [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
                guard !Task.isCancelled else { return }
                await self?.persistDraft(revision: revision)
            } catch {
                // A newer edit or explicit flush superseded this save.
            }
        }
    }

    private func validateDraft() {
        if draftTitle.count > Note.maximumTitleLength {
            saveState = .failed
            errorMessage = String(localized: "The note title cannot exceed 200 characters.")
        } else if Data(draftBody.utf8).count > Note.maximumBodyBytes {
            saveState = .failed
            errorMessage = String(localized: "The note body cannot exceed 1 MiB.")
        } else if saveState == .failed {
            saveState = .idle
            errorMessage = nil
        }
    }

    private func persistDraft(revision: Int) async {
        guard revision == draftRevision else { return }
        guard case let .snapshot(snapshot) = makeSnapshot(revision: revision) else { return }
        _ = await enqueue(snapshot).value
    }

    private func makeSnapshot(revision: Int) -> SnapshotResult {
        guard draftTitle.count <= Note.maximumTitleLength else {
            saveState = .failed
            errorMessage = String(localized: "The note title cannot exceed 200 characters.")
            return .failed
        }
        guard Data(draftBody.utf8).count <= Note.maximumBodyBytes else {
            saveState = .failed
            errorMessage = String(localized: "The note body cannot exceed 1 MiB.")
            return .failed
        }
        guard isPersistedDraft || draftHasContent else {
            saveState = .idle
            return .nothingToSave
        }
        guard hasPendingChanges else {
            saveState = .saved
            return .nothingToSave
        }

        let note = Note(
            id: draftID,
            title: draftTitle,
            body: draftBody,
            createdAt: draftCreatedAt,
            updatedAt: .now
        )
        saveState = .saving
        return .snapshot(
            DraftSnapshot(
                note: note,
                revision: revision,
                title: draftTitle,
                body: draftBody
            )
        )
    }

    private func enqueue(_ snapshot: DraftSnapshot) -> Task<NoteFlushOutcome, Never> {
        let previousSave = saveTail
        let task = Task<NoteFlushOutcome, Never> { [weak self] in
            _ = await previousSave?.value
            guard let self else { return NoteFlushOutcome.failed }
            return await persist(snapshot)
        }
        saveTail = task
        return task
    }

    private func persist(_ snapshot: DraftSnapshot) async -> NoteFlushOutcome {
        do {
            try await storage.upsertNoteThrowing(snapshot.note)
            if draftID == snapshot.note.id {
                isPersistedDraft = true
                lastPersistedTitle = snapshot.title
                lastPersistedBody = snapshot.body
            }
            if let index = notes.firstIndex(where: { $0.id == snapshot.note.id }) {
                notes[index] = snapshot.note
            } else {
                notes.append(snapshot.note)
            }
            notes.sort { $0.updatedAt > $1.updatedAt }
            if draftID == snapshot.note.id, snapshot.revision == draftRevision {
                saveState = .saved
                errorMessage = nil
            }
            return .saved
        } catch {
            if draftID == snapshot.note.id, snapshot.revision == draftRevision {
                saveState = .failed
                errorMessage = String(localized: "Note could not be saved: \(error.localizedDescription)")
            }
            return .failed
        }
    }

    private var draftHasContent: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func configureNewDraft() {
        debounceTask?.cancel()
        isConfiguringDraft = true
        draftID = UUID()
        draftCreatedAt = .now
        draftTitle = ""
        draftBody = ""
        lastPersistedTitle = ""
        lastPersistedBody = ""
        isPersistedDraft = false
        saveState = .idle
        errorMessage = nil
        isShowingDeleteConfirmation = false
        isShowingDiscardConfirmation = false
        draftRevision += 1
        draftSessionID = UUID()
        isConfiguringDraft = false
    }

    private func configureDraft(with note: Note) {
        isConfiguringDraft = true
        draftID = note.id
        draftCreatedAt = note.createdAt
        draftTitle = note.title ?? ""
        draftBody = note.body
        lastPersistedTitle = draftTitle
        lastPersistedBody = draftBody
        isPersistedDraft = true
        saveState = .saved
        errorMessage = nil
        isShowingDeleteConfirmation = false
        isShowingDiscardConfirmation = false
        draftRevision += 1
        draftSessionID = UUID()
        isConfiguringDraft = false
    }
}
