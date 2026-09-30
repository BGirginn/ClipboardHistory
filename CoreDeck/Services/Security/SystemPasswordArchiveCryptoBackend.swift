import CommonCrypto
import CryptoKit
import Foundation
import Security

struct SystemPasswordArchiveCryptoBackend: PasswordArchiveCryptoBackend {
    func randomData(count: Int) -> (status: OSStatus, data: Data) {
        guard count >= 0 else { return (errSecParam, Data()) }
        guard count > 0 else { return (errSecSuccess, Data()) }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        return (status, data)
    }

    func deriveKeyData(
        password: String,
        salt: Data,
        rounds: UInt32,
        keyLength: Int
    ) -> (status: Int32, data: Data) {
        guard keyLength >= 0 else { return (Int32(kCCParamError), Data()) }
        var keyData = Data(count: keyLength)
        let passwordData = Data(password.utf8)
        let status = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                keyData.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        passwordBytes.count,
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
