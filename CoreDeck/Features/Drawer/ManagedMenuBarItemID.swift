import Foundation

struct ManagedMenuBarItemID: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case system
        case application
    }

    let source: Source
    let ownerBundleIdentifier: String
    let semanticIdentifier: String

    var persistenceKey: String {
        [source.rawValue, ownerBundleIdentifier, semanticIdentifier]
            .map { $0.replacingOccurrences(of: "|", with: "%7C") }
            .joined(separator: "|")
    }
}
