import Foundation

protocol MigrationFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isSymbolicLink(at url: URL) throws -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}
