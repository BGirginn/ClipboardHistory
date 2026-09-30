import Foundation
import Security

enum EncryptionServiceError: LocalizedError, Sendable {
    case keychain(OSStatus)
    case invalidKey
    case invalidCiphertext
    case encryptionUnavailable

    var errorDescription: String? {
        switch self {
        case let .keychain(status): String(localized: "Keychain operation failed with status \(status).")
        case .invalidKey: String(localized: "The encryption key is invalid.")
        case .invalidCiphertext: String(localized: "Encrypted clipboard data is invalid.")
        case .encryptionUnavailable: String(localized: "Encrypted storage is currently unavailable.")
        }
    }
}
