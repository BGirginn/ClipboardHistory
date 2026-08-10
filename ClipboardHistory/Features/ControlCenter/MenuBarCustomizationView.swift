import SwiftUI

struct MenuBarCustomizationView: View {
    @ObservedObject var model: ControlCenterModel
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
            ScrollView {
                VStack(spacing: AppDesign.sectionSpacing) {
                    Toggle(
                        "Show Control Center Icon",
                        isOn: controlCenterItemBinding
                    )
                    .toggleStyle(.switch)
                    .padding(AppDesign.cardPadding)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
                    .accessibilityIdentifier("customize.controlCenterItem")

                    MenuBarMetricsConfigurationCard(model: model)

                    ForEach(model.registry.descriptors) { descriptor in
                        MenuBarFeatureConfigurationCard(model: model, descriptor: descriptor)
                    }
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
        .alert(
            "Menu Bar",
            isPresented: Binding(
                get: { model.feedbackMessage != nil },
                set: { if !$0 { model.feedbackMessage = nil } }
            )
        ) {
            Button("OK") { model.feedbackMessage = nil }
        } message: {
            Text(model.feedbackMessage ?? "")
        }
    }

    private var controlCenterItemBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.showsControlCenterItem },
            set: { isVisible in model.setControlCenterItemVisible(isVisible) }
        )
    }
}
