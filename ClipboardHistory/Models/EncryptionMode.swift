import Foundation

enum EncryptionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case sensitive
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .sensitive: String(localized: "Sensitive Items")
        case .all: String(localized: "All Items")
        }
    }
}
