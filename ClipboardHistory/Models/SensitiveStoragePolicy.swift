import Foundation

enum SensitiveStoragePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case neverSave
    case encrypted
    case ask

    var id: Self { self }

    var title: String {
        switch self {
        case .neverSave: "Never Save"
        case .encrypted: "Save Encrypted"
        case .ask: "Ask Before Saving"
        }
    }
}
