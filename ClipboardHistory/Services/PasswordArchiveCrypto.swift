import CommonCrypto
import CryptoKit
import Foundation
import Security

enum PasswordArchiveCrypto {
    private static let magic = Data("CHENC1".utf8)
    private static let rounds: UInt32 = 200_000

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw ExportImportError.passwordRequired }
        var salt = Data(count: 16)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard randomStatus == errSecSuccess else {
            throw EncryptionServiceError.keychain(randomStatus)
        }
        let key = try deriveKey(password: password, salt: salt, rounds: rounds)
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw EncryptionServiceError.invalidCiphertext
        }
        var encodedRounds = rounds.bigEndian
        return magic + salt + Data(bytes: &encodedRounds, count: MemoryLayout<UInt32>.size) + combined
    }

    static func decrypt(_ archive: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw ExportImportError.passwordRequired }
        let headerSize = magic.count + 16 + MemoryLayout<UInt32>.size
        guard archive.count > headerSize, archive.prefix(magic.count) == magic else {
            throw ExportImportError.invalidArchive
        }
        let saltStart = magic.count
        let salt = archive[saltStart..<(saltStart + 16)]
        let roundsStart = saltStart + 16
        let roundsData = archive[roundsStart..<(roundsStart + 4)]
        let rounds = roundsData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (100_000...1_000_000).contains(rounds) else {
            throw ExportImportError.invalidArchive
        }
        let key = try deriveKey(password: password, salt: Data(salt), rounds: rounds)
        do {
            let box = try AES.GCM.SealedBox(combined: archive.dropFirst(headerSize))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ExportImportError.invalidArchive
        }
    }

    static func isEncryptedArchive(_ data: Data) -> Bool {
        data.prefix(magic.count) == magic
    }

    private static func deriveKey(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let keyLength = 32
        var keyData = Data(count: keyLength)
        let result = password.withCString { passwordBytes in
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
        guard result == kCCSuccess else { throw EncryptionServiceError.invalidKey }
        return SymmetricKey(data: keyData)
    }
}
