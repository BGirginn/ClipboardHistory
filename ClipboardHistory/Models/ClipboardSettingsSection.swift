import Foundation

enum ClipboardSettingsSection: String, CaseIterable, Identifiable {
    case general
    case privacy
    case storage
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .privacy: String(localized: "Privacy")
        case .storage: String(localized: "Storage")
        case .advanced: String(localized: "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .privacy: "hand.raised"
        case .storage: "internaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }
}
