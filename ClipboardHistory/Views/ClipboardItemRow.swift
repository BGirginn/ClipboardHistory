import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    @State private var isHovering = false

    private var isSelected: Bool { viewModel.selectedItemID == item.id }
    private var isCopied: Bool { viewModel.copiedItemID == item.id }

    var body: some View {
        Button {
            viewModel.selectedItemID = item.id
            viewModel.restore(item)
        } label: {
            HStack(spacing: 0) {
                rowContent

                if isCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .padding(.trailing, 10)
                } else if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(backgroundStyle, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture().onEnded { viewModel.selectedItemID = item.id })
        .contextMenu {
            ClipboardItemContextMenu(item: item, viewModel: viewModel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies this item back to the clipboard")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("clipboard.row.\(item.id.uuidString)")
    }

    @ViewBuilder
    private var rowContent: some View {
        switch item.type {
        case .text, .richText:
            TextClipboardItemRow(item: item, isLocked: viewModel.isLocked)
        case .image, .imageGroup:
            ImageClipboardItemRow(
                item: item,
                storage: viewModel.storage,
                thumbnailService: viewModel.thumbnailService,
                isLocked: viewModel.isLocked
            )
        case .pdf, .files:
            DocumentClipboardItemRow(
                item: item,
                storage: viewModel.storage,
                thumbnailService: viewModel.thumbnailService,
                isLocked: viewModel.isLocked
            )
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected { return Color.accentColor.opacity(0.16) }
        if isHovering { return Color.primary.opacity(0.07) }
        return Color.primary.opacity(0.035)
    }

    private var accessibilityLabel: String {
        let kind: String
        switch item.type {
        case .text: kind = "Text"
        case .richText: kind = "Rich text"
        case .image: kind = "Image"
        case .imageGroup: kind = "Image group, \(item.assetFilenames.count) images"
        case .pdf: kind = "PDF"
        case .files: kind = "Files, \(item.fileURLs.count) items"
        }
        let preview = item.isSensitive || viewModel.isLocked ? "content hidden" : item.displayTitle ?? item.text ?? ""
        return "\(kind), \(preview), copied \(DateFormatting.timestamp(for: item.creationDate))"
    }

    private var accessibilityValue: String {
        [
            isSelected ? "selected" : nil,
            item.isPinned ? "pinned" : nil,
            item.isSensitive ? "sensitive" : nil,
            isCopied ? "copied" : nil,
            item.isEncrypted ? "encrypted" : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
