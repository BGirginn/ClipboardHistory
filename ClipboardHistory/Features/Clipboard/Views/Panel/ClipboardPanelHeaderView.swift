import SwiftUI

struct ClipboardPanelHeaderView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    let backToHome: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            ModuleToolbar(
                title: String(localized: "Clipboard"),
                subtitle: itemCountText,
                backTitle: String(localized: "Back to Control Center"),
                back: backToHome,
                openSettings: openSettings
            ) {
                ClipboardHistoryActionsMenu(viewModel: viewModel)
            }

            if viewModel.isLocked || viewModel.isPaused {
                ClipboardPanelStatusView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
    }

    private var itemCountText: String {
        if viewModel.items.count == 1 {
            String(localized: "1 item")
        } else {
            String(localized: "\(viewModel.items.count) items")
        }
    }

}
