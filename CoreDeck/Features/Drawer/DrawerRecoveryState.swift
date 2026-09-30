import Foundation

enum DrawerRecoveryState: String, Codable, Equatable, Sendable {
    case pending
    case restoring
    case interventionRequired
    case recovered
}
