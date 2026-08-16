import Combine
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var activeFeature: AppFeature
    @Published private(set) var settingsSection: AppSettingsSection

    private(set) var settingsReturnFeature: AppFeature

    init(
        activeFeature: AppFeature = .controlCenter,
        settingsSection: AppSettingsSection = .general
    ) {
        self.activeFeature = activeFeature
        self.settingsSection = settingsSection
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

    func openSettings(section: AppSettingsSection = .general) {
        if activeFeature != .settings {
            settingsReturnFeature = activeFeature
        }
        settingsSection = section
        activeFeature = .settings
    }

    func closeSettings() {
        activeFeature = settingsReturnFeature == .settings ? .controlCenter : settingsReturnFeature
    }

}
