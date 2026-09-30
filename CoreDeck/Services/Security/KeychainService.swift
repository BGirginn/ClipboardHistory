import Foundation
import Security

struct KeychainService: @unchecked Sendable {
    static let service = "com.brgirgin.CoreDeck.encryption"
    static let legacyService = "com.brgirgin.ClipboardHistory.encryption"
    static let account = "history-master-key-v1"
    static let notesAccount = "notes-master-key-v1"
    static let live = KeychainService(
        client: SystemKeychainSecurityClient(), account: account, legacyService: legacyService
    )
    static let notes = KeychainService(
        client: SystemKeychainSecurityClient(), account: notesAccount, legacyService: legacyService
    )

    private let client: any KeychainSecurityClient
    private let account: String
    private let legacyService: String?

    init(
        client: any KeychainSecurityClient,
        account: String = Self.account,
        legacyService: String? = nil
    ) {
        self.client = client
        self.account = account
        self.legacyService = legacyService
    }

    func loadOrCreateKey() throws -> Data {
        if let existing = try loadKey() {
            return existing
        }

        if let legacyService, let legacyKey = try loadKey(service: legacyService) {
            return try addKey(legacyKey)
        }

        let bytes = try generateRandomKey()
        return try addKey(bytes)
    }

    private func addKey(_ bytes: Data) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
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
            kSecAttrAccount as String: account
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

    private func loadKey(service: String = Self.service) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
