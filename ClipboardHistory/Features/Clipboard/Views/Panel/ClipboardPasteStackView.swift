import SwiftUI

struct ClipboardPasteStackView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Label(
                "Paste Stack: \(viewModel.pasteStackItems.count)",
                systemImage: "square.stack.3d.up"
            )
            .font(.caption.weight(.medium))
            .lineLimit(1)
            Spacer(minLength: 6)
            if let next = nextItem {
                Text(preview(for: next))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Next item: \(preview(for: next))")
            }
            Button("Paste Next", systemImage: "arrow.right.to.line", action: pasteNext)
            .labelStyle(.iconOnly)
            .help("Paste the next stack item to the active app")
            .accessibilityIdentifier("pasteStack.next")
            Button("Reset Paste Stack", systemImage: "xmark.circle", action: reset)
            .labelStyle(.iconOnly)
            .help("Reset Paste Stack")
            .accessibilityIdentifier("pasteStack.reset")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55))
        .accessibilityIdentifier("pasteStack.bar")
    }

    private var nextItem: ClipboardItem? {
        switch viewModel.settings.pasteStackOrder {
        case .fifo: viewModel.pasteStackItems.first
        case .lifo: viewModel.pasteStackItems.last
        }
    }

    private func preview(for item: ClipboardItem) -> String {
        guard !viewModel.isLocked, !item.isSensitive else {
            return item.isSensitive
                ? String(localized: "Sensitive content")
                : String(localized: "Clipboard History is locked")
        }
        return item.displayTitle ?? item.text ?? item.contentSubtype.rawValue
    }

    func pasteNext() {
        viewModel.pasteNextStackItem()
    }

    func reset() {
        viewModel.resetPasteStack()
    }
}
