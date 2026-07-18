import Foundation

enum DatabaseError: LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String)
    case preparationFailed(String)
    case bindingFailed
    case corrupt
    case encryptionUnavailable
    case closed

    var errorDescription: String? {
        switch self {
        case let .openFailed(message): "Unable to open the history database: \(message)"
        case let .executionFailed(message): "Database operation failed: \(message)"
        case let .preparationFailed(message): "Database statement failed: \(message)"
        case .bindingFailed: "A database value could not be bound."
        case .corrupt: "The history database failed its integrity check."
        case .encryptionUnavailable: "Encrypted storage is unavailable."
        case .closed: "The history database is closed."
        }
    }
}
