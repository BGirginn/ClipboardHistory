import Foundation

struct ClipboardArchive: Codable, Sendable {
    static let currentVersion = 3

    let version: Int
    let createdAt: Date
    let mode: ClipboardExportMode
    let items: [ClipboardItem]
    let assets: [String: Data]
    let collections: [ClipboardCollection]
    let notes: [Note]
    let itemHashes: [String: String]
    let assetHashes: [String: String]
    let collectionHashes: [String: String]
    let noteHashes: [String: String]

    init(
        version: Int,
        createdAt: Date,
        mode: ClipboardExportMode,
        items: [ClipboardItem],
        assets: [String: Data],
        collections: [ClipboardCollection] = [],
        notes: [Note] = [],
        itemHashes: [String: String] = [:],
        assetHashes: [String: String] = [:],
        collectionHashes: [String: String] = [:],
        noteHashes: [String: String] = [:]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.mode = mode
        self.items = items
        self.assets = assets
        self.collections = collections
        self.notes = notes
        self.itemHashes = itemHashes
        self.assetHashes = assetHashes
        self.collectionHashes = collectionHashes
        self.noteHashes = noteHashes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mode = try container.decode(ClipboardExportMode.self, forKey: .mode)
        items = try container.decode([ClipboardItem].self, forKey: .items)
        assets = try container.decode([String: Data].self, forKey: .assets)
        collections = try container.decodeIfPresent([ClipboardCollection].self, forKey: .collections) ?? []
        notes = version >= 3
            ? try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
            : []
        itemHashes = try container.decodeIfPresent([String: String].self, forKey: .itemHashes) ?? [:]
        assetHashes = try container.decodeIfPresent([String: String].self, forKey: .assetHashes) ?? [:]
        collectionHashes = try container.decodeIfPresent([String: String].self, forKey: .collectionHashes) ?? [:]
        noteHashes = version >= 3
            ? try container.decodeIfPresent([String: String].self, forKey: .noteHashes) ?? [:]
            : [:]
    }
}
