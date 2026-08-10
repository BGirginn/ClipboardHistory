import SwiftUI

struct KeyboardCleaningView: View {
    @ObservedObject var controller: KeyboardCleaningController
    let isLocked: Bool
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "Keyboard Cleaning"),
                subtitle: controller.isActive
                    ? String(localized: "Keyboard Cleaning is active")
                    : String(localized: "Ready"),
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) { EmptyView() }
            Divider()
            ScrollView {
                KeyboardCleaningCardView(controller: controller, isLocked: isLocked)
                    .padding(AppDesign.horizontalPadding)
            }
        }
    }
}
