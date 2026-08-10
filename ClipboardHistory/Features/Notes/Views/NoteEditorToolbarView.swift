import SwiftUI

struct NoteEditorToolbarView: View {
    @ObservedObject var controller: NoteController
    let close: () -> Void
    let openSettings: () -> Void
    let beginModalInteraction: () -> Void
    let endModalInteraction: () -> Void
    let menuCommandDidRun: () -> Void

    var body: some View {
        ModuleToolbar(
            title: String(localized: "Note"),
            subtitle: nil,
            backTitle: String(localized: "Back to Notes"),
            back: close,
            openSettings: openSettings
        ) {
            if controller.canDeleteDraft {
                Button("Delete Note", systemImage: "trash", role: .destructive, action: showDeleteConfirmation)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(
                        width: ClipboardPanelLayout.compactControlSize,
                        height: ClipboardPanelLayout.compactControlSize
                    )
                    .help("Delete Note")
                    .accessibilityIdentifier("notes.delete")
                    .confirmationDialog(
                        "Delete this note?",
                        isPresented: $controller.isShowingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Note", role: .destructive, action: deleteNote)
                            .accessibilityIdentifier("notes.delete.confirm")
                        Button("Cancel", role: .cancel, action: cancelDelete)
                    } message: {
                        Text("This cannot be undone.")
                    }
            }
        }
        .onChange(of: controller.isShowingDeleteConfirmation) { _, isPresented in
            if !isPresented {
                endModalInteraction()
            }
        }
    }

    private func showDeleteConfirmation() {
        beginModalInteraction()
        controller.isShowingDeleteConfirmation = true
    }

    private func deleteNote() {
        menuCommandDidRun()
        endModalInteraction()
        Task { await controller.deleteDraft() }
    }

    private func cancelDelete() {
        menuCommandDidRun()
        endModalInteraction()
    }
}
