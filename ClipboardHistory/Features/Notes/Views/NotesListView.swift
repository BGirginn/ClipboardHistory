import SwiftUI

struct NotesListView: View {
    @ObservedObject var controller: NoteController
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "Notes"),
                subtitle: noteCountText,
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) {
                Button("New Note", systemImage: "square.and.pencil", action: controller.requestNewNote)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                    .help("New Note (Command-N)")
                    .accessibilityIdentifier("notes.new")
            }

            NotesSearchField(text: $controller.searchText)
                .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
                .padding(.bottom, 10)

            Divider()

            if controller.notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "note.text",
                    description: Text("Create a note without leaving the menu bar.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.filteredNotes.isEmpty {
                ContentUnavailableView.search(text: controller.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(controller.filteredNotes) { note in
                            Button {
                                controller.openEditor(for: note)
                            } label: {
                                NoteRowView(note: note)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("notes.row.\(note.id.uuidString.lowercased())")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .accessibilityIdentifier("notes.list")
            }
        }
        .task { await controller.loadIfNeeded() }
    }

    private var noteCountText: String {
        controller.notes.count == 1
            ? String(localized: "1 note")
            : String(localized: "\(controller.notes.count) notes")
    }
}
