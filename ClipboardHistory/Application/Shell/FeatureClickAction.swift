import Foundation

enum FeatureClickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case open
    case toggleClipboardRecording
    case newNote
    case toggleKeyboardCleaning
    case toggleScrollReverse
    case muteAllAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: String(localized: "Open Controls")
        case .toggleClipboardRecording: String(localized: "Pause or Resume Recording")
        case .newNote: String(localized: "New Note")
        case .toggleKeyboardCleaning: String(localized: "Start or Stop Keyboard Cleaning")
        case .toggleScrollReverse: String(localized: "Enable or Disable Scroll Reverse")
        case .muteAllAudio: String(localized: "Mute or Restore All Audio")
        }
    }
}
