import Foundation
import Security

@testable import CoreDeckTestHost

struct FailingMasterKeyProvider: MasterKeyProvider {
    func loadOrCreateKey() throws -> Data {
        throw EncryptionServiceError.keychain(errSecAuthFailed)
    }

    func replaceKey(with newKey: Data) throws {
        throw EncryptionServiceError.keychain(errSecAuthFailed)
    }
}
