import Foundation

enum DuplicateDetectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case newest
    case lastTen
    case lastHour
    case fullHistory

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: String(localized: "Newest Item")
        case .lastTen: String(localized: "Last 10 Items")
        case .lastHour: String(localized: "Last Hour")
        case .fullHistory: String(localized: "Full History")
        }
    }
}
