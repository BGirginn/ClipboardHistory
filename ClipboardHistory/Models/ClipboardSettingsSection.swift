import Foundation

enum ClipboardSettingsSection: String, CaseIterable, Identifiable {
    case general
    case privacy
    case security
    case storage
    case systemMonitor
    case audio
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .privacy: String(localized: "Privacy")
        case .security: String(localized: "Security")
        case .storage: String(localized: "Storage")
        case .systemMonitor: String(localized: "System Monitor")
        case .audio: String(localized: "Audio and Browsers")
        case .advanced: String(localized: "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .privacy: "hand.raised"
        case .security: "lock.shield"
        case .storage: "internaldrive"
        case .systemMonitor: "gauge.with.dots.needle.67percent"
        case .audio: "speaker.wave.2"
        case .advanced: "slider.horizontal.3"
        }
    }
}
