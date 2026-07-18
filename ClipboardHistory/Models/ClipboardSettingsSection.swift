import Foundation

enum ClipboardSettingsSection: String, CaseIterable, Identifiable {
    case general
    case privacy
    case security
    case storage
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .privacy: "Privacy"
        case .security: "Security"
        case .storage: "Storage"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .privacy: "hand.raised"
        case .security: "lock.shield"
        case .storage: "internaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }
}
