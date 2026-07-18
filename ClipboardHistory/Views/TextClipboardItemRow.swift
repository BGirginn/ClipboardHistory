import SwiftUI

struct TextClipboardItemRow: View {
    let item: ClipboardItem
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.type == .richText ? "doc.richtext" : "clipboard")
                .font(.title3)
                .foregroundStyle(item.isSensitive ? .orange : .secondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if isLocked || item.isSensitive {
                    Label(item.isSensitive ? "Sensitive content" : "Clipboard History is locked", systemImage: "eye.slash")
                        .lineLimit(1)
                } else {
                    Text(item.text ?? "")
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.disabled)
                }

                HStack(spacing: 6) {
                    Text(item.contentSubtype.displayName)
                    Text("•")
                    Text(DateFormatting.timestamp(for: item.creationDate))
                    if item.isEncrypted {
                        Image(systemName: "lock.fill")
                            .accessibilityLabel("Encrypted")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }
}

private extension ClipboardContentSubtype {
    var displayName: String {
        switch self {
        case .plainText: "Text"
        case .url: "URL"
        case .email: "Email"
        case .filePath: "File Path"
        case .sourceCode: "Source Code"
        case .rtf: "RTF"
        case .html: "HTML"
        case .image: "Image"
        case .imageGroup: "Images"
        case .pdf: "PDF"
        case .file: "File"
        case .files: "Files"
        case .unknown: "Content"
        }
    }
}

#Preview {
    TextClipboardItemRow(
        item: ClipboardItem(
            type: .text,
            text: "A copied text item that can span up to three lines in the history.",
            hash: "preview"
        ),
        isLocked: false
    )
    .frame(width: 360)
    .padding()
}
