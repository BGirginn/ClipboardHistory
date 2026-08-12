import Foundation

struct ClipboardPrivateMetadataV2: Codable, Equatable, Sendable {
    var protectedMetadata: ClipboardProtectedMetadata
    var fileURLs: [String]
    var fileBookmarks: [Data]

    init(
        protectedMetadata: ClipboardProtectedMetadata,
        fileURLs: [String] = [],
        fileBookmarks: [Data] = []
    ) {
        self.protectedMetadata = protectedMetadata
        self.fileURLs = fileURLs
        self.fileBookmarks = fileBookmarks
    }
}
