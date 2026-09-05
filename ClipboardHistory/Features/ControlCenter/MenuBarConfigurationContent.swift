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
        Form {
            if scope == .all {
                Section {
                    MenuBarPreview(model: model)
                }
                MenuBarPresetSection(model: model)
            }

            if !model.areRequestedMenuBarItemsVisible {
                Section {
                    Label(
                        "macOS is not currently showing one or more requested menu-bar items.",
                        systemImage: "exclamationmark.triangle"
                    )
                    if let destination = Self.menuBarSettingsURL {
                        Link("Open Menu Bar Settings", destination: destination)
                    }
                }
            }

            if scope != .metrics {
                Section {
                    Toggle(
                        "Show Control Center Icon",
                        isOn: controlCenterItemBinding
                    )
                    .accessibilityIdentifier("customize.controlCenterItem")
                } header: {
                    Text("Control Center")
                } footer: {
                    Text("Hiding this icon keeps ClipboardHistory available in the Dock.")
                }
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
        .formStyle(.grouped)
        .accessibilityIdentifier("customize.form")
    }

    private static let menuBarSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.MenuBar-Settings.extension"
    )

    private var controlCenterItemBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.showsControlCenterItem },
            set: { model.setControlCenterItemVisible($0) }
        )
    }
}
