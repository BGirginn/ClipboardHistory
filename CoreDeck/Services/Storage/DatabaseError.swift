import Foundation

enum DatabaseError: LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String)
    case preparationFailed(String)
    case bindingFailed
    case corrupt
    case encryptionUnavailable
    case unsafeFilename
    case closed
    case recoveryRequired
    case legacyApplicationRunning
    case migrationConflict

    var errorDescription: String? {
        switch self {
        case let .openFailed(message): String(localized: "Unable to open the history database: \(message)")
        case let .executionFailed(message): String(localized: "Database operation failed: \(message)")
        case let .preparationFailed(message): String(localized: "Database statement failed: \(message)")
        case .bindingFailed: String(localized: "A database value could not be bound.")
        case .corrupt: String(localized: "The history database failed its integrity check.")
        case .encryptionUnavailable: String(localized: "Encrypted storage is unavailable.")
        case .unsafeFilename: String(localized: "A managed asset filename is unsafe.")
        case .closed: String(localized: "The history database is closed.")
        case .recoveryRequired: String(localized: "History recovery is required. Recovery files were preserved. Restart the application to retry recovery.")
        case .legacyApplicationRunning: String(localized: "Quit the previous CoreDeck version before migrating its data.")
        case .migrationConflict: String(localized: "Both old and new CoreDeck data directories exist. Neither was changed; resolve the conflict before continuing.")
        }
    }
}
