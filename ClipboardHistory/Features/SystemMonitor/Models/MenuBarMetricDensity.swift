import Foundation

enum MenuBarMetricDensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact
    case standard

    var id: String { rawValue }
    var visibleMetricLimit: Int { self == .compact ? 2 : 3 }

    var title: String {
        switch self {
        case .compact: String(localized: "Compact (2 metrics)")
        case .standard: String(localized: "Standard (3 metrics)")
        }
    }
}
