import Foundation

@MainActor
protocol ExternalMenuBarItemObserving {
    func observation(for id: ManagedMenuBarItemID) async throws -> DrawerItemObservation?
}
