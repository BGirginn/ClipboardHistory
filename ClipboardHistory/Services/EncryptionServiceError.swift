import Foundation
import Security

enum EncryptionServiceError: LocalizedError, Sendable {
    case keychain(OSStatus)
    case invalidKey
    case invalidCiphertext
    case encryptionUnavailable

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Keychain operation failed with status \(status)."
        case .invalidKey: "The encryption key is invalid."
        case .invalidCiphertext: "Encrypted clipboard data is invalid."
        case .encryptionUnavailable: "Encrypted storage is currently unavailable."
        }
    }
}
