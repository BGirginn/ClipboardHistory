import SwiftUI

struct NotesListView: View {
    @ObservedObject var controller: NoteController
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Clipboard History", systemImage: "chevron.left", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .help("Back to Clipboard History")
                    .accessibilityIdentifier("notes.back")

                VStack(alignment: .leading, spacing: 1) {
                    Text("Notes")
                        .font(.headline)
                    Text(
                        "\(controller.notes.count) \(controller.notes.count == 1 ? String(localized: "note") : String(localized: "notes"))"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("New Note", systemImage: "square.and.pencil", action: controller.requestNewNote)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .help("New Note (Command-N)")
                    .accessibilityIdentifier("notes.new")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            TextField("Search Notes", text: $controller.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .accessibilityIdentifier("notes.search")

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
                List(controller.filteredNotes) { note in
                    Button {
                        controller.openEditor(for: note)
                    } label: {
                        NoteRowView(note: note)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notes.row.\(note.id.uuidString.lowercased())")
                }
                .listStyle(.inset)
                .accessibilityIdentifier("notes.list")
            }
        }
        .task { await controller.loadIfNeeded() }
    }
}
