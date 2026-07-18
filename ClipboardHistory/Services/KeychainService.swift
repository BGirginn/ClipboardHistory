import Foundation
import Security

enum KeychainService {
    private static let service = "com.brgirgin.ClipboardHistory.encryption"
    private static let account = "history-master-key-v1"

    static func loadOrCreateKey() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }

        let bytes = try generateRandomKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let existing = try loadKey() {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw EncryptionServiceError.keychain(addStatus)
        }
        return bytes
    }

    static func rotateKey(with newKey: Data) throws {
        guard newKey.count == 32 else { throw EncryptionServiceError.invalidKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
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

    private static func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
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
