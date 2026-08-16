import SwiftUI

struct ClipboardItemRow: View, @MainActor Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let isCopied: Bool
    let storage: StorageService
    let thumbnailService: ThumbnailService
    let actions: ClipboardItemActions

    @State private var isHovering: Bool

    init(
        item: ClipboardItem,
        isSelected: Bool,
        isCopied: Bool,
        storage: StorageService,
        thumbnailService: ThumbnailService,
        actions: ClipboardItemActions,
        isHovering: Bool = false
    ) {
        self.item = item
        self.isSelected = isSelected
        self.isCopied = isCopied
        self.storage = storage
        self.thumbnailService = thumbnailService
        self.actions = actions
        _isHovering = State(initialValue: isHovering)
    }

    var body: some View {
        Button(action: selectAndCopy) {
            HStack(spacing: 0) {
                ClipboardItemRowContent(
                    item: item,
                    storage: storage,
                    thumbnailService: thumbnailService
                )

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
        .onHover(perform: updateHover)
        .onDrag(dragProvider)
        .contextMenu {
            ClipboardItemContextMenu(item: item, actions: actions)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies this item back to the clipboard")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("clipboard.row.\(item.id.uuidString)")
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
        let preview = item.isSensitive ? "content hidden" : item.displayTitle ?? item.text ?? ""
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

    func selectAndCopy() {
        actions.selectAndCopy(item)
    }

    func updateHover(_ hovering: Bool) {
        isHovering = hovering
    }

    func dragProvider() -> NSItemProvider {
        actions.dragProvider(item)
    }

    static func == (lhs: ClipboardItemRow, rhs: ClipboardItemRow) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.isCopied == rhs.isCopied
    }
}
