import Foundation

struct ClipboardProtectedMetadata: Codable, Equatable, Sendable {
    var displayTitle: String?
    var tags: [String]
    var extractedText: String?
    var qrCodeText: String?
    var colorHex: String?

    init(
        displayTitle: String? = nil,
        tags: [String] = [],
        extractedText: String? = nil,
        qrCodeText: String? = nil,
        colorHex: String? = nil
    ) {
        self.displayTitle = displayTitle
        self.tags = tags
        self.extractedText = extractedText
        self.qrCodeText = qrCodeText
        self.colorHex = colorHex
    }
}
