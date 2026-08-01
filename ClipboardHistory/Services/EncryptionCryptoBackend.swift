import CryptoKit
import Foundation

protocol EncryptionCryptoBackend: Sendable {
    func seal(_ data: Data, using key: SymmetricKey) throws -> Data?
    func open(_ data: Data, using key: SymmetricKey) throws -> Data
}

struct SystemEncryptionCryptoBackend: EncryptionCryptoBackend {
    func seal(_ data: Data, using key: SymmetricKey) throws -> Data? {
        try AES.GCM.seal(data, using: key).combined
    }

    func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}
