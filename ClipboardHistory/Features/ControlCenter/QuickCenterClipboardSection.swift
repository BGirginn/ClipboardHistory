import SwiftUI

struct QuickCenterClipboardSection: View {
    @ObservedObject var controller: ClipboardHistoryViewModel
    let openClipboard: () -> Void

    private var recentItems: [ClipboardItem] {
        Array((controller.pinnedItems + controller.recentItems).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Clipboard", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                Button(action: openClipboard) {
                    Label(String(localized: "Open Clipboard"), systemImage: "chevron.right")
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open Clipboard")
                    .accessibilityIdentifier("controlCenter.clipboard")
            }

            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("quickCenter.clipboard.error")
            } else if recentItems.isEmpty {
                ContentUnavailableView(
                    "No Clipboard Items",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something to make it available here.")
                )
                .frame(minHeight: 72)
            } else {
                ForEach(recentItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: systemImage(for: item.type))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(summary(for: item))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Paste as Plain Text", systemImage: "textformat") {
                            controller.paste(item, as: .plainText)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Paste as Plain Text")
                        .accessibilityIdentifier("quickCenter.clipboard.plainText.\(item.id)")
                        Button(item.isPinned ? "Unpin" : "Pin", systemImage: pinImage(for: item)) {
                            controller.togglePin(item)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(item.isPinned ? "Unpin" : "Pin")
                        .accessibilityIdentifier("quickCenter.clipboard.pin.\(item.id)")
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
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
        .accessibilityIdentifier("quickCenter.clipboard")
    }

    private func summary(for item: ClipboardItem) -> String {
        if item.isSensitive { return String(localized: "Sensitive content hidden") }
        if let title = item.displayTitle, !title.isEmpty { return title }
        if let text = item.text, !text.isEmpty { return text }
        return fallbackTitle(for: item.type)
    }

    private func pinImage(for item: ClipboardItem) -> String {
        item.isPinned ? "pin.slash" : "pin"
    }

    private func systemImage(for type: ClipboardItemType) -> String {
        switch type {
        case .text, .richText: "doc.text"
        case .image, .imageGroup: "photo"
        case .pdf: "doc.richtext"
        case .files: "doc.on.doc"
        }
    }

    private func fallbackTitle(for type: ClipboardItemType) -> String {
        switch type {
        case .text: String(localized: "Text")
        case .richText: String(localized: "Rich Text")
        case .image: String(localized: "Image")
        case .imageGroup: String(localized: "Images")
        case .pdf: String(localized: "PDF")
        case .files: String(localized: "Files")
        }
    }
}
