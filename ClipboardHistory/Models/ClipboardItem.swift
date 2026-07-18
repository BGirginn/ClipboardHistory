import Foundation

struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var type: ClipboardItemType
    var text: String?
    var imageFilename: String?
    var creationDate: Date
    var hash: String
    var isPinned: Bool
    var pinnedAt: Date?
    var lastUsedAt: Date?
    var useCount: Int
    var displayTitle: String?
    var thumbnailFilename: String?
    var contentSubtype: ClipboardContentSubtype
    var expiresAt: Date?
    var isSensitive: Bool
    var sourceApplicationBundleID: String?
    var storageVersion: Int
    var payloadFilename: String?
    var assetFilenames: [String]
    var fileURLs: [String]
    var fileBookmarks: [Data]
    var imageWidth: Int?
    var imageHeight: Int?
    var pageCount: Int?
    var fileSize: Int64?
    var isEncrypted: Bool

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        text: String? = nil,
        imageFilename: String? = nil,
        creationDate: Date = .now,
        hash: String,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        displayTitle: String? = nil,
        thumbnailFilename: String? = nil,
        contentSubtype: ClipboardContentSubtype = .plainText,
        expiresAt: Date? = nil,
        isSensitive: Bool = false,
        sourceApplicationBundleID: String? = nil,
        storageVersion: Int = 2,
        payloadFilename: String? = nil,
        assetFilenames: [String] = [],
        fileURLs: [String] = [],
        fileBookmarks: [Data] = [],
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        pageCount: Int? = nil,
        fileSize: Int64? = nil,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.imageFilename = imageFilename
        self.creationDate = creationDate
        self.hash = hash
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.displayTitle = displayTitle
        self.thumbnailFilename = thumbnailFilename
        self.contentSubtype = contentSubtype
        self.expiresAt = expiresAt
        self.isSensitive = isSensitive
        self.sourceApplicationBundleID = sourceApplicationBundleID
        self.storageVersion = storageVersion
        self.payloadFilename = payloadFilename
        self.assetFilenames = assetFilenames
        self.fileURLs = fileURLs
        self.fileBookmarks = fileBookmarks
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.isEncrypted = isEncrypted
    }

    var isStructurallyValid: Bool {
        guard !hash.isEmpty else { return false }

        switch type {
        case .text:
            return text != nil && imageFilename == nil
        case .image:
            return text == nil && imageFilename?.isEmpty == false
        case .richText:
            return text != nil
        case .pdf:
            return payloadFilename?.isEmpty == false
        case .files:
            return !fileURLs.isEmpty
        case .imageGroup:
            return !assetFilenames.isEmpty
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ClipboardItemType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        hash = try container.decode(String.self, forKey: .hash)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        thumbnailFilename = try container.decodeIfPresent(String.self, forKey: .thumbnailFilename)
        contentSubtype = try container.decodeIfPresent(ClipboardContentSubtype.self, forKey: .contentSubtype)
            ?? Self.legacySubtype(for: type)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        sourceApplicationBundleID = try container.decodeIfPresent(
            String.self,
            forKey: .sourceApplicationBundleID
        )
        storageVersion = try container.decodeIfPresent(Int.self, forKey: .storageVersion) ?? 1
        payloadFilename = try container.decodeIfPresent(String.self, forKey: .payloadFilename)
        assetFilenames = try container.decodeIfPresent([String].self, forKey: .assetFilenames) ?? []
        fileURLs = try container.decodeIfPresent([String].self, forKey: .fileURLs) ?? []
        fileBookmarks = try container.decodeIfPresent([Data].self, forKey: .fileBookmarks) ?? []
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
    }

    private static func legacySubtype(for type: ClipboardItemType) -> ClipboardContentSubtype {
        switch type {
        case .text: .plainText
        case .image: .image
        case .richText: .rtf
        case .pdf: .pdf
        case .files: .file
        case .imageGroup: .imageGroup
        }
    }
}
