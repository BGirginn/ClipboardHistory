import SwiftUI

struct NoteEditorSurfaceView: View {
    @Binding var title: String
    @Binding var bodyText: String
    let bodyFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            TextField("Optional Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .lineLimit(1...2)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityLabel("Note Title")
                .accessibilityIdentifier("notes.editor.title")

            Divider()
                .padding(.horizontal, 12)

            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("Start typing…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused(bodyFocus)
                    .accessibilityLabel("Note Body")
                    .accessibilityIdentifier("notes.editor.body")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: ClipboardPanelLayout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipboardPanelLayout.cardCornerRadius)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        }
        .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
        .padding(.top, 12)
    }
}
