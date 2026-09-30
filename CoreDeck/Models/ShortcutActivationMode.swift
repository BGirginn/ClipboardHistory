import Foundation

enum ShortcutActivationMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case hold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: String(localized: "Press to Open or Close")
        case .hold: String(localized: "Hold, Select, Release to Paste")
        }
    }
}
