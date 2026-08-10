import Combine
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var activeFeature: AppFeature

    private(set) var settingsReturnFeature: AppFeature
    private(set) var featureBeforeLock: AppFeature?

    init(activeFeature: AppFeature = .controlCenter) {
        self.activeFeature = activeFeature
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

    func openSettings() {
        if activeFeature != .settings {
            settingsReturnFeature = activeFeature
        }
        activeFeature = .settings
    }

    func closeSettings() {
        activeFeature = settingsReturnFeature == .settings ? .controlCenter : settingsReturnFeature
    }

    func applicationLockDidChange(isLocked: Bool) {
        if isLocked {
            featureBeforeLock = activeFeature
        } else {
            featureBeforeLock = nil
        }
    }
}
