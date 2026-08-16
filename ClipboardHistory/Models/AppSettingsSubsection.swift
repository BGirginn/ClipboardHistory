import Foundation

enum AppSettingsSubsection: String, Identifiable {
    case appPresentation
    case appStartup
    case menuBarItems
    case menuBarMetrics
    case clipboardGeneral
    case clipboardPrivacy
    case clipboardStorage
    case clipboardAdvanced
    case notesGeneral
    case notesSecurity
    case notesSaving
    case inputKeyboardCleaning
    case inputScrollReverse
    case systemTemperature
    case systemNetwork
    case audioSystem
    case audioChromium
    case audioSafari
    case audioReset

    var id: Self { self }

    var title: String {
        switch self {
        case .appPresentation: String(localized: "Presentation")
        case .appStartup: String(localized: "Startup")
        case .menuBarItems: String(localized: "Modules")
        case .menuBarMetrics: String(localized: "Metrics")
        case .clipboardGeneral, .notesGeneral: String(localized: "General")
        case .clipboardPrivacy: String(localized: "Privacy")
        case .notesSecurity: String(localized: "Security")
        case .clipboardStorage: String(localized: "Storage")
        case .clipboardAdvanced: String(localized: "Advanced")
        case .notesSaving: String(localized: "Saving")
        case .inputKeyboardCleaning: String(localized: "Keyboard Cleaning")
        case .inputScrollReverse: String(localized: "Scroll Reverse")
        case .systemTemperature: String(localized: "Temperature")
        case .systemNetwork: String(localized: "Network")
        case .audioSystem: String(localized: "System Audio")
        case .audioChromium: String(localized: "Chromium")
        case .audioSafari: String(localized: "Safari")
        case .audioReset: String(localized: "Reset")
        }
    }

    var systemImage: String {
        switch self {
        case .appPresentation: "paintbrush"
        case .appStartup: "power"
        case .menuBarItems: "square.grid.2x2"
        case .menuBarMetrics: "waveform.path.ecg"
        case .clipboardGeneral, .notesGeneral: "switch.2"
        case .clipboardPrivacy: "hand.raised"
        case .notesSecurity: "lock.shield"
        case .clipboardStorage: "internaldrive"
        case .clipboardAdvanced: "slider.horizontal.3"
        case .notesSaving: "checkmark.circle"
        case .inputKeyboardCleaning: "keyboard.badge.ellipsis"
        case .inputScrollReverse: "arrow.up.arrow.down.circle"
        case .systemTemperature: "thermometer.medium"
        case .systemNetwork: "network"
        case .audioSystem: "speaker.wave.2"
        case .audioChromium: "puzzlepiece.extension"
        case .audioSafari: "safari"
        case .audioReset: "arrow.counterclockwise"
        }
    }

    var clipboardSection: ClipboardSettingsSection? {
        switch self {
        case .clipboardGeneral: .general
        case .clipboardPrivacy: .privacy
        case .clipboardStorage: .storage
        case .clipboardAdvanced: .advanced
        default: nil
        }
    }
}
