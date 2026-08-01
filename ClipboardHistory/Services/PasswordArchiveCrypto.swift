import CommonCrypto
import CryptoKit
import Foundation

enum PasswordArchiveCrypto {
    private static let magic = Data("CHENC1".utf8)
    private static let rounds: UInt32 = 200_000

    static func encrypt(
        _ plaintext: Data,
        password: String,
        backend: any PasswordArchiveCryptoBackend = SystemPasswordArchiveCryptoBackend()
    ) throws -> Data {
        guard !password.isEmpty else { throw ExportImportError.passwordRequired }
        let random = backend.randomData(count: 16)
        guard random.status == errSecSuccess else {
            throw EncryptionServiceError.keychain(random.status)
        }
        let key = try deriveKey(
            password: password,
            salt: random.data,
            rounds: rounds,
            backend: backend
        )
        guard let combined = try backend.seal(plaintext, using: key) else {
            throw EncryptionServiceError.invalidCiphertext
        }
        var encodedRounds = rounds.bigEndian
        return magic + random.data + Data(bytes: &encodedRounds, count: MemoryLayout<UInt32>.size) + combined
    }

    static func decrypt(
        _ archive: Data,
        password: String,
        backend: any PasswordArchiveCryptoBackend = SystemPasswordArchiveCryptoBackend()
    ) throws -> Data {
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
        let key = try deriveKey(
            password: password,
            salt: Data(salt),
            rounds: rounds,
            backend: backend
        )
        do {
            return try backend.open(Data(archive.dropFirst(headerSize)), using: key)
        } catch {
            throw ExportImportError.invalidArchive
        }
    }

    static func isEncryptedArchive(_ data: Data) -> Bool {
        data.prefix(magic.count) == magic
    }

    private static func deriveKey(
        password: String,
        salt: Data,
        rounds: UInt32,
        backend: any PasswordArchiveCryptoBackend
    ) throws -> SymmetricKey {
        let keyLength = 32
        let derived = backend.deriveKeyData(
            password: password,
            salt: salt,
            rounds: rounds,
            keyLength: keyLength
        )
        guard derived.status == kCCSuccess, derived.data.count == keyLength else {
            throw EncryptionServiceError.invalidKey
        }
        return SymmetricKey(data: derived.data)
    }
}
