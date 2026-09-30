import Foundation

enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case balanced
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: String(localized: "Minimal")
        case .balanced: String(localized: "Balanced")
        case .custom: String(localized: "Custom")
        }
    }

    var summary: String {
        switch self {
        case .minimal:
            String(localized: "Keep only the Control Center icon in the menu bar.")
        case .balanced:
            String(localized: "Show three live metrics and reveal module icons only when they need attention.")
        case .custom:
            String(localized: "Keep your current menu-bar choices and adjust each item below.")
        }
    }
}
