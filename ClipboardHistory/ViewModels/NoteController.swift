import Combine
import Foundation

@MainActor
final class NoteController: ObservableObject {
    enum Route: Hashable {
        case editor
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    private struct DraftSnapshot: Sendable {
        let note: Note
        let generation: Int
        let title: String
        let body: String
    }

    @Published var notes: [Note] = []
    @Published var searchText = ""
    @Published var path: [Route] = []
    @Published var draftTitle = "" {
        didSet { draftDidChange() }
    }
    @Published var draftBody = "" {
        didSet { draftDidChange() }
    }
    @Published var errorMessage: String?
    @Published var saveState: SaveState = .idle
    @Published var isShowingDeleteConfirmation = false

    private let storage: StorageService
    private let debounceDuration: Duration
    private var debounceTask: Task<Void, Never>?
    private var immediateSaveTask: Task<Void, Never>?
    private var saveGeneration = 0
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
        configureNewDraft()
        path = [.editor]
        Task { [weak self] in
            await self?.loadIfNeeded()
        }
    }

    func requestNewNote() {
        guard path.last == .editor else {
            configureNewDraft()
            path = [.editor]
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await flushPendingSave()
            configureNewDraft()
            path = [.editor]
        }
    }

    func openEditor(for note: Note) {
        debounceTask?.cancel()
        configureDraft(with: note)
        path = [.editor]
    }

    func showList() {
        path.removeAll()
    }

    func saveImmediately() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let snapshot = makeSnapshot(generation: saveGeneration) else { return }
        let previousSave = immediateSaveTask
        immediateSaveTask = Task { [weak self] in
            await previousSave?.value
            await self?.persist(snapshot)
        }
    }

    func flushPendingSave() async {
        debounceTask?.cancel()
        debounceTask = nil
        let snapshot = makeSnapshot(generation: saveGeneration)
        await immediateSaveTask?.value
        guard let snapshot else { return }
        await persist(snapshot)
    }

    func deleteDraft() async {
        guard isPersistedDraft else {
            configureNewDraft()
            showList()
            return
        }
        do {
            debounceTask?.cancel()
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
        saveGeneration += 1
        validateDraft()
        debounceTask?.cancel()
        let generation = saveGeneration
        debounceTask = Task { [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
                guard !Task.isCancelled else { return }
                await self?.persistDraft(generation: generation)
            } catch {
                // A newer edit or an explicit flush superseded this save.
            }
        }
    }

    private func validateDraft() {
        if draftTitle.count > Note.maximumTitleLength {
            errorMessage = String(localized: "The note title cannot exceed 200 characters.")
        } else if Data(draftBody.utf8).count > Note.maximumBodyBytes {
            errorMessage = String(localized: "The note body cannot exceed 1 MiB.")
        } else if saveState == .failed {
            errorMessage = nil
            saveState = .idle
        }
    }

    private func persistDraft(generation: Int) async {
        guard generation == saveGeneration else { return }
        guard let snapshot = makeSnapshot(generation: generation) else { return }
        await persist(snapshot)
    }

    private func makeSnapshot(generation: Int) -> DraftSnapshot? {
        guard draftTitle.count <= Note.maximumTitleLength else {
            saveState = .failed
            errorMessage = String(localized: "The note title cannot exceed 200 characters.")
            return nil
        }
        guard Data(draftBody.utf8).count <= Note.maximumBodyBytes else {
            saveState = .failed
            errorMessage = String(localized: "The note body cannot exceed 1 MiB.")
            return nil
        }
        guard isPersistedDraft || draftHasContent else {
            saveState = .idle
            return nil
        }
        guard draftTitle != lastPersistedTitle || draftBody != lastPersistedBody else {
            saveState = .saved
            return nil
        }

        let note = Note(
            id: draftID,
            title: draftTitle,
            body: draftBody,
            createdAt: draftCreatedAt,
            updatedAt: .now
        )
        saveState = .saving
        return DraftSnapshot(
            note: note,
            generation: generation,
            title: draftTitle,
            body: draftBody
        )
    }

    private func persist(_ snapshot: DraftSnapshot) async {
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
            if draftID == snapshot.note.id, snapshot.generation == saveGeneration {
                saveState = .saved
                errorMessage = nil
            }
        } catch {
            if draftID == snapshot.note.id, snapshot.generation == saveGeneration {
                saveState = .failed
                errorMessage = String(localized: "Note could not be saved: \(error.localizedDescription)")
            }
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
        saveGeneration += 1
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
        saveGeneration += 1
        isConfiguringDraft = false
    }
}
