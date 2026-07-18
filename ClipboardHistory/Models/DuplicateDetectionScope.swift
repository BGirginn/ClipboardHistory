import Foundation

enum DuplicateDetectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case newest
    case lastTen
    case lastHour
    case fullHistory

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: "Newest Item"
        case .lastTen: "Last 10 Items"
        case .lastHour: "Last Hour"
        case .fullHistory: "Full History"
        }
    }
}
