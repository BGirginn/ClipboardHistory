import SwiftUI

struct InputToolsSettingsView: View {
    @ObservedObject private var keyboardCleaning: KeyboardCleaningController
    @ObservedObject private var scrollReversal: ScrollReversalController
    let selectedSubsection: AppSettingsSubsection

    init(
        inputTools: InputToolsController,
        selectedSubsection: AppSettingsSubsection = .inputKeyboardCleaning
    ) {
        _keyboardCleaning = ObservedObject(wrappedValue: inputTools.keyboardCleaning)
        _scrollReversal = ObservedObject(wrappedValue: inputTools.scrollReversal)
        self.selectedSubsection = selectedSubsection
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppDesign.sectionSpacing) {
                if selectedSubsection == .inputKeyboardCleaning {
                    KeyboardCleaningCardView(controller: keyboardCleaning)
                }
                if selectedSubsection == .inputScrollReverse {
                    ScrollReversalCardView(controller: scrollReversal)
                }
            }
            .padding(AppDesign.horizontalPadding)
        }
        .accessibilityIdentifier("settings.inputTools")
    }
}
