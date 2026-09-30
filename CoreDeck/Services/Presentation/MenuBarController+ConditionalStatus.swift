import Combine

@MainActor
extension MenuBarController {
    func observeConditionalMenuBarStates() {
        keyboardCleaningCancellable = appModel.inputTools.keyboardCleaning.$isActive
            .removeDuplicates()
            .sink { [weak self] isActive in
                self?.refreshConditionalStatusItems(keyboardCleaningActive: isActive)
            }
        scrollReversalCancellable = appModel.inputTools.scrollReversal.$isActive
            .removeDuplicates()
            .sink { [weak self] isActive in
                self?.refreshConditionalStatusItems(scrollReversalActive: isActive)
            }
        audioMixerCancellable = appModel.audioMixer.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.refreshConditionalStatusItems()
            }
        }
    }

    func stopConditionalMenuBarObservation() {
        keyboardCleaningCancellable = nil
        scrollReversalCancellable = nil
        audioMixerCancellable = nil
    }
}
