import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var model: ControlCenterModel
    let selectedSubsection: AppSettingsSubsection

    init(
        model: ControlCenterModel,
        selectedSubsection: AppSettingsSubsection = .menuBarItems
    ) {
        self.model = model
        self.selectedSubsection = selectedSubsection
    }

    var body: some View {
        ScrollView {
            MenuBarConfigurationContent(
                model: model,
                scope: selectedSubsection == .menuBarMetrics ? .metrics : .items
            )
                .padding(AppDesign.horizontalPadding)
        }
    }
}
