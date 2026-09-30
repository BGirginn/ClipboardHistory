import Foundation

enum MenuBarMetricStyle: String, CaseIterable, Codable, Identifiable {
    case compact
    case value
    case iconAndValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "Value Only")
        case .value: String(localized: "Label and Value")
        case .iconAndValue: String(localized: "Icon and Value")
        }
    }
}
