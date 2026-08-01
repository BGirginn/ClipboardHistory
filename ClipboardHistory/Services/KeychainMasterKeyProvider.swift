import Foundation

struct KeychainMasterKeyProvider: MasterKeyProvider {
    static let active = KeychainMasterKeyProvider()

    func loadOrCreateKey() throws -> Data {
        try KeychainService.loadOrCreateKey()
    }

    func replaceKey(with newKey: Data) throws {
        try KeychainService.rotateKey(with: newKey)
    }
}
