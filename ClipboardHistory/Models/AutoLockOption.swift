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
        case .never: "Never"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        case .fifteenMinutes: "After 15 Minutes"
        case .whenMacLocks: "When Mac Locks"
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
