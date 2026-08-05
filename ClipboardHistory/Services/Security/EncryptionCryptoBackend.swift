import CryptoKit
import Foundation

protocol EncryptionCryptoBackend: Sendable {
    func seal(_ data: Data, using key: SymmetricKey) throws -> Data?
    func open(_ data: Data, using key: SymmetricKey) throws -> Data
}
