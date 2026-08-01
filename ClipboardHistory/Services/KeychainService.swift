import Foundation
import Security

protocol KeychainSecurityClient {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func randomData(count: Int) -> (status: OSStatus, data: Data)
}

struct KeychainService: @unchecked Sendable {
    static let service = "com.brgirgin.ClipboardHistory.encryption"
    static let account = "history-master-key-v1"
    static let live = KeychainService(client: SystemKeychainSecurityClient())

    private let client: any KeychainSecurityClient

    init(client: any KeychainSecurityClient) {
        self.client = client
    }

    func loadOrCreateKey() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }

        let bytes = try generateRandomKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: bytes
        ]
        let addStatus = client.add(query)
        if addStatus == errSecDuplicateItem, let existing = try loadKey() {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw EncryptionServiceError.keychain(addStatus)
        }
        return bytes
    }

    func rotateKey(with newKey: Data) throws {
        guard newKey.count == 32 else { throw EncryptionServiceError.invalidKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let attributes: [String: Any] = [kSecValueData as String: newKey]
        let status = client.update(query, attributes: attributes)
        guard status == errSecSuccess else {
            throw EncryptionServiceError.keychain(status)
        }
    }

    static func generateRandomKey() throws -> Data {
        try live.generateRandomKey()
    }

    func generateRandomKey() throws -> Data {
        let result = client.randomData(count: 32)
        guard result.status == errSecSuccess else {
            throw EncryptionServiceError.keychain(result.status)
        }
        guard result.data.count == 32 else {
            throw EncryptionServiceError.invalidKey
        }
        return result.data
    }

    private func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let result = client.copyMatching(query)
        if result.status == errSecItemNotFound {
            return nil
        }
        guard result.status == errSecSuccess else {
            throw EncryptionServiceError.keychain(result.status)
        }
        guard let data = result.data, data.count == 32 else {
            throw EncryptionServiceError.invalidKey
        }
        return data
    }
}
