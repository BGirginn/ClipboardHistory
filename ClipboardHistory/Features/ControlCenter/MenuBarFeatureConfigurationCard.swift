import SwiftUI

struct MenuBarFeatureConfigurationCard: View {
    @ObservedObject var model: ControlCenterModel
    let descriptor: FeatureDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(descriptor.title, systemImage: descriptor.systemImage)
                .font(.headline)
            Text(descriptor.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Show in Control Center", isOn: controlCenterBinding)
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).center")
            Toggle("Show Separate Menu-Bar Icon", isOn: standaloneBinding)
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).standalone")
            Picker("Left Click", selection: clickActionBinding) {
                ForEach(descriptor.supportedClickActions) { action in
                    Text(descriptor.title(for: action)).tag(action)
                }
            }
            .accessibilityIdentifier("customize.\(descriptor.id.rawValue).action")
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cardCornerRadius)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var controlCenterBinding: Binding<Bool> {
        Binding(
            get: { model.configuration(for: descriptor.id).placement.showsInControlCenter },
            set: { model.setShownInControlCenter($0, for: descriptor.id) }
        )
    }

    private var standaloneBinding: Binding<Bool> {
        Binding(
            get: { model.configuration(for: descriptor.id).placement.showsStandaloneItem },
            set: { model.setStandaloneItemVisible($0, for: descriptor.id) }
        )
    }

    private var clickActionBinding: Binding<FeatureClickAction> {
        Binding(
            get: { model.configuration(for: descriptor.id).clickAction },
            set: { model.setClickAction($0, for: descriptor.id) }
        )
    }
}
