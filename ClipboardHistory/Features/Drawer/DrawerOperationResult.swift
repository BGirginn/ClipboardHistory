import Foundation

enum DrawerOperationResult: Equatable, Sendable {
    case succeeded(DrawerItemObservation)
    case failed(message: String, recovery: DrawerRecoveryState)
}
