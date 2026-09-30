import Foundation

enum MemoryPressureLevel: String, Equatable, Sendable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Elevated")
        case .critical: String(localized: "Critical")
        }
    }
}
