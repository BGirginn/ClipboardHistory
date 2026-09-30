import Foundation

enum AppSettingsSection: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case clipboard
    case notes
    case inputTools
    case systemMonitor
    case audioMixer

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .clipboard: String(localized: "Clipboard")
        case .notes: String(localized: "Notes")
        case .inputTools: String(localized: "Input Tools")
        case .systemMonitor: String(localized: "System Monitor")
        case .audioMixer: String(localized: "Audio Mixer")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .menuBar: "menubar.rectangle"
        case .clipboard: "clipboard"
        case .notes: "note.text"
        case .inputTools: "keyboard"
        case .systemMonitor: "gauge.with.dots.needle.67percent"
        case .audioMixer: "slider.horizontal.3"
        }
    }

    var subsections: [AppSettingsSubsection] {
        switch self {
        case .general:
            [.appPresentation, .appStartup]
        case .menuBar:
            [.menuBarItems, .menuBarMetrics]
        case .clipboard:
            [
                .clipboardGeneral,
                .clipboardPrivacy,
                .clipboardStorage,
                .clipboardAdvanced
            ]
        case .notes:
            [.notesGeneral, .notesSecurity, .notesSaving]
        case .inputTools:
            [.inputKeyboardCleaning, .inputScrollReverse]
        case .systemMonitor:
            [.systemTemperature, .systemNetwork]
        case .audioMixer:
            [.audioSystem, .audioChromium, .audioSafari, .audioReset]
        }
    }

    var defaultSubsection: AppSettingsSubsection {
        switch self {
        case .general: .appPresentation
        case .menuBar: .menuBarItems
        case .clipboard: .clipboardGeneral
        case .notes: .notesGeneral
        case .inputTools: .inputKeyboardCleaning
        case .systemMonitor: .systemTemperature
        case .audioMixer: .audioSystem
        }
    }
}
