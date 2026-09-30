import Foundation

enum ClipboardFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case images
    case pinned
    case snippets

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .text: String(localized: "Text")
        case .images: String(localized: "Images")
        case .pinned: String(localized: "Pinned")
        case .snippets: String(localized: "Snippets")
        }
    }
}
