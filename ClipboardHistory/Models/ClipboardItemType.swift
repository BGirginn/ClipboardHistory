import Foundation

enum ClipboardItemType: String, Codable, Sendable {
    case text
    case image
    case richText
    case pdf
    case files
    case imageGroup
}
