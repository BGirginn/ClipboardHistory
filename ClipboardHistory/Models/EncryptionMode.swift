import Foundation

enum EncryptionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case sensitive
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .sensitive: "Sensitive Items"
        case .all: "All Items"
        }
    }
}
