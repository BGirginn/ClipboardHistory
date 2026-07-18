import Foundation

enum ClipboardSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst
    case recentlyUsed

    var id: Self { self }

    var title: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .recentlyUsed: "Recently Used"
        }
    }
}
