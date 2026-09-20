import SwiftUI

struct QuickCenterNoteSection: View {
    @ObservedObject var controller: NoteController
    let openNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quick Note", systemImage: "square.and.pencil")
                    .font(.headline)
                Spacer()
                saveStatus
                Button("Open Notes", systemImage: "chevron.right", action: openNotes)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open Notes")
                    .accessibilityIdentifier("controlCenter.notes")
            }

            TextField("Optional Title", text: $controller.draftTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("quickNote.title")
            TextEditor(text: $controller.draftBody)
                .font(.body)
                .frame(minHeight: 64, idealHeight: 72, maxHeight: 88)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }
                .accessibilityLabel("Note Body")
                .accessibilityIdentifier("quickNote.body")

            if let error = controller.errorMessage {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry Save", action: controller.retrySave)
                        .controlSize(.small)
                        .accessibilityIdentifier("quickNote.retry")
                }
            } else {
                HStack {
                    Text("Your draft is shared with Notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save", action: controller.saveImmediately)
                        .controlSize(.small)
                        .disabled(!controller.hasPendingChanges)
                        .accessibilityIdentifier("quickNote.save")
                }
            }
        }
        .padding(AppDesign.compactCardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cardCornerRadius)
                .stroke(.separator, lineWidth: 1)
        }
        .task { controller.prepareQuickDraft() }
        .accessibilityIdentifier("quickCenter.quickNote")
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch controller.saveState {
        case .idle:
            if controller.hasPendingChanges {
                Image(systemName: "circle.dotted")
                    .help("Unsaved Changes")
                    .accessibilityLabel("Unsaved Changes")
            }
        case .saving:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Saving…")
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Saved")
                .accessibilityLabel("Saved")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Save failed")
                .accessibilityLabel("Save failed")
        }
    }
}
