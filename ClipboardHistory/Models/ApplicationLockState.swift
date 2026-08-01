import Foundation

enum ApplicationLockState: String, Codable, Sendable {
    case disabled
    case unlocked
    case locked

    var isEnabled: Bool {
        self != .disabled
    }

    var isLocked: Bool {
        self == .locked
    }
}
