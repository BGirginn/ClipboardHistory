import Foundation

struct KeychainMasterKeyProvider: MasterKeyProvider {
    let backend: KeychainBackend

    static var active: KeychainMasterKeyProvider {
        #if COMMUNITY
        KeychainMasterKeyProvider(backend: .login)
        #else
        KeychainMasterKeyProvider(backend: .dataProtection)
        #endif
    }

    func loadOrCreateKey() throws -> Data {
        try KeychainService.loadOrCreateKey(backend: backend)
    }

    func replaceKey(with newKey: Data) throws {
        try KeychainService.rotateKey(with: newKey, backend: backend)
    }
}
