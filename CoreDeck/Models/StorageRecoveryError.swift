import Foundation

enum StorageRecoveryError: LocalizedError, Sendable {
    case installationFailed(previousDatabaseRestored: Bool, underlyingDescription: String)

    var previousDatabaseRestored: Bool {
        switch self {
        case let .installationFailed(restored, _): restored
        }
    }

    var errorDescription: String? {
        switch self {
        case let .installationFailed(true, underlying):
            String(localized: "Recovery installation failed and the previous database was restored: \(underlying)")
        case let .installationFailed(false, underlying):
            String(localized: "Recovery installation failed and rollback could not be verified: \(underlying)")
        }
    }
}
