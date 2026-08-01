import Foundation

enum SensitiveStoragePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case neverSave
    case encrypted
    case ask

    var id: Self { self }

    var title: String {
        switch self {
        case .neverSave: String(localized: "Never Save")
        case .encrypted: String(localized: "Save Encrypted")
        case .ask: String(localized: "Ask Before Saving")
        }
    }
}
