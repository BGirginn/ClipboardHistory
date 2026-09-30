import Foundation

@MainActor
protocol ExternalMenuBarItemMoving {
    func move(_ item: DrawerItemObservation, to placement: DrawerPlacement) async throws
    func restore(_ item: DrawerItemObservation) async throws
}
