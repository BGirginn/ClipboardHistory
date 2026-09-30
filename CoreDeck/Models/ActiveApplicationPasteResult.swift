import Foundation

enum ActiveApplicationPasteResult: Equatable, Sendable {
    case pasted
    case permissionRequired
    case targetUnavailable
    case eventCreationFailed
}
