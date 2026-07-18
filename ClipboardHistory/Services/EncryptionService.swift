import CryptoKit
import Foundation

struct EncryptionService: Sendable {
    private let key: SymmetricKey

    private init(key: SymmetricKey) {
        self.key = key
    }

    init(keyData: Data) throws {
        guard keyData.count == 32 else { throw EncryptionServiceError.invalidKey }
        key = SymmetricKey(data: keyData)
    }

    static func live(
        keyLoader: () throws -> Data = KeychainService.loadOrCreateKey
    ) throws -> EncryptionService {
        try EncryptionService(keyData: keyLoader())
    }

    static func ephemeral() -> EncryptionService {
        EncryptionService(key: SymmetricKey(size: .bits256))
    }

    func encrypt(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw EncryptionServiceError.invalidCiphertext
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionServiceError.invalidCiphertext
        }
    }
}
