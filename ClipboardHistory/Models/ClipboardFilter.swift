import Foundation

enum ClipboardFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case images
    case pinned

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .pinned: "Pinned"
        }
    }
}
