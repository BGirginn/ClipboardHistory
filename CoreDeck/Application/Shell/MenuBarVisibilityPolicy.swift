import Foundation

enum MenuBarVisibilityPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case hidden
    case whenActive
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: String(localized: "Hidden")
        case .whenActive: String(localized: "When Active")
        case .always: String(localized: "Always")
        }
    }
}
