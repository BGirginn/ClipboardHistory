import Foundation

enum ClipboardExportMode: String, Codable, Sendable {
    case metadataOnly
    case fullUnencrypted
    case encrypted
}
