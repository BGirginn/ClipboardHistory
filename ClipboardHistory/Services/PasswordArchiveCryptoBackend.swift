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

struct SystemPasswordArchiveCryptoBackend: PasswordArchiveCryptoBackend {
    func randomData(count: Int) -> (status: OSStatus, data: Data) {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return (status, data)
    }

    func deriveKeyData(
        password: String,
        salt: Data,
        rounds: UInt32,
        keyLength: Int
    ) -> (status: Int32, data: Data) {
        var keyData = Data(count: keyLength)
        let status = password.withCString { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                keyData.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes,
                        strlen(passwordBytes),
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return (status, keyData)
    }

    func seal(_ data: Data, using key: SymmetricKey) throws -> Data? {
        try AES.GCM.seal(data, using: key).combined
    }

    func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}
