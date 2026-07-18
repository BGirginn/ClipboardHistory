import Foundation

struct ClipboardArchive: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let mode: ClipboardExportMode
    let items: [ClipboardItem]
    let assets: [String: Data]
}
