import SwiftUI

struct MenuBarFeatureConfigurationCard: View {
    @ObservedObject var model: ControlCenterModel
    let descriptor: FeatureDescriptor

    var body: some View {
        Section {
            Toggle("Show in Control Center", isOn: controlCenterBinding)
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).center")
            Toggle("Show in Drawer", isOn: drawerBinding)
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).drawer")
            if descriptor.id != .systemMonitor {
                Picker("Menu Bar", selection: visibilityBinding) {
                    ForEach(descriptor.supportedMenuBarVisibilityPolicies) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(model.configuration(for: descriptor.id).placement.showsInDrawer)
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).standalone")
            }
            if descriptor.id == .keyboardCleaning {
                LabeledContent("Left Click", value: String(localized: "Toggle Keyboard Cleaning"))
            } else if descriptor.supportedClickActions.count == 1,
                      let action = descriptor.supportedClickActions.first {
                LabeledContent("Left Click", value: descriptor.title(for: action))
            } else {
                Picker("Left Click", selection: clickActionBinding) {
                    ForEach(descriptor.supportedClickActions) { action in
                        Text(descriptor.title(for: action)).tag(action)
                    }
                }
                .accessibilityIdentifier("customize.\(descriptor.id.rawValue).action")
            }
        } header: {
            Label(descriptor.title, systemImage: descriptor.systemImage)
        } footer: {
            Text(descriptor.summary)
        }
    }

    private var controlCenterBinding: Binding<Bool> {
        Binding(
            get: { model.configuration(for: descriptor.id).placement.showsInControlCenter },
            set: { model.setShownInControlCenter($0, for: descriptor.id) }
        )
    }

    private var visibilityBinding: Binding<MenuBarVisibilityPolicy> {
        Binding(
            get: { model.configuration(for: descriptor.id).placement.menuBarVisibility },
            set: { model.setMenuBarVisibility($0, for: descriptor.id) }
        )
    }

    private var drawerBinding: Binding<Bool> {
        Binding(
            get: { model.configuration(for: descriptor.id).placement.showsInDrawer },
            set: { model.setShownInDrawer($0, for: descriptor.id) }
        )
    }

    private var clickActionBinding: Binding<FeatureClickAction> {
        Binding(
            get: { model.configuration(for: descriptor.id).clickAction },
            set: { model.setClickAction($0, for: descriptor.id) }
        )
    }
}
