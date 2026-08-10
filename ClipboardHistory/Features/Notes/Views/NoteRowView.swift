import SwiftUI

struct NoteRowView: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.resolvedTitle ?? String(localized: "Untitled Note"))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(note.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        let value = note.body
            .replacing("\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? String(localized: "Empty note") : value
    }
}
