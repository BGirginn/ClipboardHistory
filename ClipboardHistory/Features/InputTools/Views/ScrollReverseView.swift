import SwiftUI

struct ScrollReverseView: View {
    @ObservedObject var controller: ScrollReversalController
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "Scroll Reverse"),
                subtitle: controller.isActive
                    ? String(localized: "Scroll Reverse is active")
                    : String(localized: "Native scrolling is unchanged"),
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) { EmptyView() }
            Divider()
            ScrollView {
                ScrollReversalCardView(controller: controller)
                    .padding(AppDesign.horizontalPadding)
            }
        }
    }
}
