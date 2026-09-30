import Foundation

struct DrawerOperationJournal: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Phase: String, Codable, Sendable {
        case prepared
        case moved
        case restoring
        case restoreFailed
    }

    let version: Int
    let operationID: UUID
    let createdAt: Date
    let requestedPlacement: DrawerPlacement
    let original: DrawerItemObservation
    var observed: DrawerItemObservation?
    var phase: Phase
    var failure: String?
}
