import SwiftUI

struct MenuBarPresetSection: View {
    @ObservedObject var model: ControlCenterModel

    var body: some View {
        Section {
            Picker("Layout", selection: presetBinding) {
                ForEach(MenuBarPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            Text(model.selectedPreset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Layout Preset")
        }
    }

    private var presetBinding: Binding<MenuBarPreset> {
        Binding(
            get: { model.selectedPreset },
            set: { model.applyPreset($0) }
        )
    }
}
