import SwiftUI

struct MenuBarConfigurationContent: View {
    enum Scope {
        case all
        case items
        case metrics
    }

    @ObservedObject var model: ControlCenterModel
    let scope: Scope

    init(model: ControlCenterModel, scope: Scope = .all) {
        self.model = model
        self.scope = scope
    }

    var body: some View {
        VStack(spacing: AppDesign.sectionSpacing) {
            if scope != .metrics {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Show Control Center Icon",
                        isOn: controlCenterItemBinding
                    )
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("customize.controlCenterItem")
                    Text("Hiding this icon keeps ClipboardHistory available in the Dock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(AppDesign.cardPadding)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
            }

            if scope != .items {
                MenuBarMetricsConfigurationCard(model: model)
            }

            if scope != .metrics {
                ForEach(model.registry.descriptors) { descriptor in
                    MenuBarFeatureConfigurationCard(model: model, descriptor: descriptor)
                }
            }
        }
    }

    private var controlCenterItemBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.showsControlCenterItem },
            set: { model.setControlCenterItemVisible($0) }
        )
    }
}
