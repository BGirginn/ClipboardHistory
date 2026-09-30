import Foundation

enum ClipboardSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst
    case recentlyUsed

    var id: Self { self }

    var title: String {
        switch self {
        case .newestFirst: String(localized: "Newest First")
        case .oldestFirst: String(localized: "Oldest First")
        case .recentlyUsed: String(localized: "Recently Used")
        }
    }
}
