@preconcurrency import CryptoKit
import Foundation

struct EncryptionService: Sendable {
    private let key: SymmetricKey
    private let cryptoBackend: any EncryptionCryptoBackend

    private init(
        key: SymmetricKey,
        cryptoBackend: any EncryptionCryptoBackend
    ) {
        self.key = key
        self.cryptoBackend = cryptoBackend
    }

    init(
        keyData: Data,
        cryptoBackend: any EncryptionCryptoBackend = SystemEncryptionCryptoBackend()
    ) throws {
        guard keyData.count == 32 else { throw EncryptionServiceError.invalidKey }
        key = SymmetricKey(data: keyData)
        self.cryptoBackend = cryptoBackend
    }

    static func live(
        keyLoader: () throws -> Data
    ) throws -> EncryptionService {
        try EncryptionService(keyData: keyLoader())
    }

    static func ephemeral(
        cryptoBackend: any EncryptionCryptoBackend = SystemEncryptionCryptoBackend()
    ) -> EncryptionService {
        EncryptionService(
            key: SymmetricKey(size: .bits256),
            cryptoBackend: cryptoBackend
        )
    }

    func encrypt(_ data: Data) throws -> Data {
        guard let combined = try cryptoBackend.seal(data, using: key) else {
            throw EncryptionServiceError.invalidCiphertext
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        do {
            return try cryptoBackend.open(data, using: key)
        } catch {
            throw EncryptionServiceError.invalidCiphertext
        }
    }
}
