import Combine
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var activeFeature: AppFeature
    @Published private(set) var settingsSection: AppSettingsSection?
    @Published private(set) var settingsSubsection: AppSettingsSubsection?

    private(set) var settingsReturnFeature: AppFeature

    init(
        activeFeature: AppFeature = .controlCenter,
        settingsSection: AppSettingsSection? = nil,
        settingsSubsection: AppSettingsSubsection? = nil
    ) {
        self.activeFeature = activeFeature
        self.settingsSection = settingsSection
        self.settingsSubsection = settingsSubsection
        settingsReturnFeature = activeFeature
    }

    func showControlCenter() {
        activeFeature = .controlCenter
    }

    func showClipboard() {
        activeFeature = .clipboard
    }

    func showNotes() {
        activeFeature = .notes
    }

    func showKeyboardCleaning() {
        activeFeature = .keyboardCleaning
    }

    func showScrollReverse() {
        activeFeature = .scrollReverse
    }

    func showSystemMonitor() {
        activeFeature = .systemMonitor
    }

    func showAudioMixer() {
        activeFeature = .audioMixer
    }

    func showMenuBarCustomization() {
        activeFeature = .menuBarCustomization
    }

    func openSettings(section: AppSettingsSection? = nil) {
        if activeFeature != .settings {
            settingsReturnFeature = activeFeature
        }
        settingsSubsection = nil
        settingsSection = section
        activeFeature = .settings
    }

    func closeSettings() {
        activeFeature = settingsReturnFeature == .settings ? .controlCenter : settingsReturnFeature
    }

    func selectSettingsSubsection(_ subsection: AppSettingsSubsection?) {
        guard activeFeature == .settings,
              settingsSubsection != subsection else { return }
        settingsSubsection = subsection
        settingsSection = subsection?.section
    }

}
