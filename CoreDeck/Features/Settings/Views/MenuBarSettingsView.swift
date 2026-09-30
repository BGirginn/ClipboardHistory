import SwiftUI

struct MenuBarSettingsView: View {
    let model: ControlCenterModel
    let selectedSubsection: AppSettingsSubsection

    init(
        model: ControlCenterModel,
        selectedSubsection: AppSettingsSubsection = .menuBarItems
    ) {
        self.model = model
        self.selectedSubsection = selectedSubsection
    }

    var body: some View {
        MenuBarConfigurationContent(
            model: model,
            scope: selectedSubsection == .menuBarMetrics ? .metrics : .items
        )
    }
}
