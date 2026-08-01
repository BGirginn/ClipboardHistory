import Foundation

enum AutoLockOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case never
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case whenMacLocks

    var id: Self { self }

    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .oneMinute: String(localized: "After 1 Minute")
        case .fiveMinutes: String(localized: "After 5 Minutes")
        case .fifteenMinutes: String(localized: "After 15 Minutes")
        case .whenMacLocks: String(localized: "When Mac Locks")
        }
    }

    var inactivityDuration: Duration? {
        switch self {
        case .never, .whenMacLocks: nil
        case .oneMinute: .seconds(60)
        case .fiveMinutes: .seconds(300)
        case .fifteenMinutes: .seconds(900)
        }
    }
}
