import Foundation

struct RichTextPayload: Codable, Equatable, Sendable {
    let rtfData: Data?
    let htmlData: Data?
}
