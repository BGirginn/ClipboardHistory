import SwiftUI

struct NoteEditorStatusView: View {
    @ObservedObject var controller: NoteController
    let beginModalInteraction: () -> Void
    let endModalInteraction: () -> Void
    let menuCommandDidRun: () -> Void

    var body: some View {
        Group {
            if let errorMessage = controller.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("notes.editor.error")

                    if controller.saveState == .failed {
                        HStack {
                            Button("Retry Save", action: controller.retrySave)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("notes.editor.retry")
                            Button("Discard Unsaved Changes", role: .destructive) {
                                beginModalInteraction()
                                controller.isShowingDiscardConfirmation = true
                            }
                            .accessibilityIdentifier("notes.editor.discard")
                            .confirmationDialog(
                                "Discard unsaved changes?",
                                isPresented: $controller.isShowingDiscardConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Discard Changes", role: .destructive) {
                                    menuCommandDidRun()
                                    endModalInteraction()
                                    controller.discardChanges()
                                }
                                Button("Cancel", role: .cancel) {
                                    menuCommandDidRun()
                                    endModalInteraction()
                                }
                            } message: {
                                Text("The last successfully saved version will be kept.")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 8))
                .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 6) {
                    switch controller.saveState {
                    case .idle:
                        EmptyView()
                    case .saving:
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("Saving…")
                    case .saved:
                        Label("Saved", systemImage: "checkmark.circle.fill")
                    case .failed:
                        Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 0)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("notes.editor.saveStatus")
            }
        }
        .onChange(of: controller.isShowingDiscardConfirmation) { _, isPresented in
            if !isPresented {
                endModalInteraction()
            }
        }
    }

}
