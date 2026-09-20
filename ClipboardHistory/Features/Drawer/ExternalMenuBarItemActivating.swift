import Foundation

@MainActor
protocol ExternalMenuBarItemActivating {
    func activate(_ request: DrawerActivationRequest) async throws
}
