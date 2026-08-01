import Foundation

protocol MasterKeyProvider: Sendable {
    func loadOrCreateKey() throws -> Data
    func replaceKey(with newKey: Data) throws
}
