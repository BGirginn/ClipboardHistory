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
                Text(next.displayTitle ?? next.text ?? next.contentSubtype.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Next item: \(next.displayTitle ?? next.contentSubtype.rawValue)")
            }
            Button("Paste Next", systemImage: "arrow.right.to.line") {
                viewModel.pasteNextStackItem()
            }
            .labelStyle(.iconOnly)
            .help("Paste the next stack item to the active app")
            .accessibilityIdentifier("pasteStack.next")
            Button("Reset Paste Stack", systemImage: "xmark.circle") {
                viewModel.resetPasteStack()
            }
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
}
