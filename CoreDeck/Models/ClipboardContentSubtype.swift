import Foundation

enum ClipboardContentSubtype: String, Codable, CaseIterable, Sendable {
    case plainText
    case url
    case email
    case filePath
    case sourceCode
    case color
    case rtf
    case html
    case image
    case imageGroup
    case pdf
    case file
    case files
    case unknown
}
