import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var controller: NoteController
    @FocusState private var bodyIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Notes", systemImage: "chevron.left", action: closeEditor)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .help("Back to Notes")
                    .accessibilityIdentifier("notes.editor.back")

                Spacer()

                Text("Note")
                    .font(.headline)

                Spacer()

                if controller.canDeleteDraft {
                    Button("Delete Note", systemImage: "trash") {
                        controller.isShowingDeleteConfirmation = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .help("Delete Note")
                    .accessibilityIdentifier("notes.delete")
                } else {
                    Color.clear
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            TextField("Optional Title", text: $controller.draftTitle)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .accessibilityLabel("Note Title")
                .accessibilityIdentifier("notes.editor.title")

            ZStack(alignment: .topLeading) {
                if controller.draftBody.isEmpty {
                    Text("Start typing…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $controller.draftBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .focused($bodyIsFocused)
                    .accessibilityLabel("Note Body")
                    .accessibilityIdentifier("notes.editor.body")
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("notes.editor.error")
            } else if controller.saveState != .idle {
                Text(saveStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("notes.editor.saveStatus")
            }
        }
        .task {
            await Task.yield()
            bodyIsFocused = true
        }
        .onDisappear {
            controller.saveImmediately()
        }
        .overlay {
            if controller.isShowingDeleteConfirmation {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text("Delete this note?")
                            .font(.headline)
                        Text("This cannot be undone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Cancel", role: .cancel) {
                                controller.isShowingDeleteConfirmation = false
                            }
                            Button("Delete Note", role: .destructive) {
                                Task { await controller.deleteDraft() }
                            }
                            .accessibilityIdentifier("notes.delete.confirm")
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .shadow(radius: 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("notes.delete.confirmation")
                }
            }
        }
    }

    private var saveStatus: String {
        switch controller.saveState {
        case .idle: ""
        case .saving: String(localized: "Saving…")
        case .saved: String(localized: "Saved")
        case .failed: String(localized: "Save failed")
        }
    }

    private func closeEditor() {
        controller.saveImmediately()
        controller.showList()
    }
}
