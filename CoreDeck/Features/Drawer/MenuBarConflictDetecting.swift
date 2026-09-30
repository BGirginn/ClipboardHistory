import Foundation

@MainActor
protocol MenuBarConflictDetecting {
    func hasConflict(in observations: [DrawerItemObservation]) async -> Bool
}
