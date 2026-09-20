import Foundation

@MainActor
protocol ExternalMenuBarItemDiscovering {
    func discoverItems() async throws -> [DrawerItemObservation]
}
