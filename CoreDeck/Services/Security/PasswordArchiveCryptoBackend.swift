import CommonCrypto
import CryptoKit
import Foundation
import Security

protocol PasswordArchiveCryptoBackend {
    func randomData(count: Int) -> (status: OSStatus, data: Data)
    func deriveKeyData(
        password: String,
        salt: Data,
        rounds: UInt32,
        keyLength: Int
    ) -> (status: Int32, data: Data)
    func seal(_ data: Data, using key: SymmetricKey) throws -> Data?
    func open(_ data: Data, using key: SymmetricKey) throws -> Data
}
