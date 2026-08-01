import Foundation
import Security

enum KeychainService {
    private static let account = "history-master-key-v1"

    static func loadOrCreateKey() throws -> Data {
        try loadOrCreateKey(backend: KeychainMasterKeyProvider.active.backend)
    }

    static func loadOrCreateKey(backend: KeychainBackend) throws -> Data {
        if let existing = try loadKey(backend: backend) {
            return existing
        }

        let bytes = try generateRandomKey()

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backend.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: bytes
        ]
        if backend.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let existing = try loadKey(backend: backend) {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw EncryptionServiceError.keychain(addStatus)
        }
        return bytes
    }

    static func rotateKey(with newKey: Data) throws {
        try rotateKey(with: newKey, backend: KeychainMasterKeyProvider.active.backend)
    }

    static func rotateKey(with newKey: Data, backend: KeychainBackend) throws {
        guard newKey.count == 32 else { throw EncryptionServiceError.invalidKey }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backend.service,
            kSecAttrAccount as String: account
        ]
        if backend.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        let attributes: [String: Any] = [kSecValueData as String: newKey]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw EncryptionServiceError.keychain(status)
        }
    }

    static func generateRandomKey() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else {
            throw EncryptionServiceError.keychain(status)
        }
        return bytes
    }

    private static func loadKey(backend: KeychainBackend) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: backend.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if backend.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw EncryptionServiceError.keychain(status)
        }
        guard let data = result as? Data, data.count == 32 else {
            throw EncryptionServiceError.invalidKey
        }
        return data
    }

}
