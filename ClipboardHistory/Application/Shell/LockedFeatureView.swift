import SwiftUI

struct LockedFeatureView: View {
    let title: String
    let backToHome: () -> Void
    let openSettings: () -> Void
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: title,
                subtitle: String(localized: "Locked"),
                backTitle: String(localized: "Back to Control Center"),
                back: backToHome,
                openSettings: openSettings
            ) {
                EmptyView()
            }
            Divider()
            ClipboardLockedHistoryView(unlock: unlock)
        }
    }
}
