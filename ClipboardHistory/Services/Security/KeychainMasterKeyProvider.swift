import Foundation

struct KeychainMasterKeyProvider: MasterKeyProvider {
    static let active = KeychainMasterKeyProvider()
    private let service: KeychainService

    init(service: KeychainService = .live) {
        self.service = service
    }

    func loadOrCreateKey() throws -> Data {
        try service.loadOrCreateKey()
    }

    func replaceKey(with newKey: Data) throws {
        try service.rotateKey(with: newKey)
    }
}
