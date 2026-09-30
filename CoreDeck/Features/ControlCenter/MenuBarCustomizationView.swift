import SwiftUI

struct MenuBarCustomizationView: View {
    let model: ControlCenterModel
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "Customize Menu Bar"),
                subtitle: String(localized: "Changes apply immediately"),
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) { EmptyView() }
            Divider()
            MenuBarConfigurationContent(model: model)
        }
    }
}
