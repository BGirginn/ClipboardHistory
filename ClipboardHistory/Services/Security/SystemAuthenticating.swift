import Foundation

@MainActor
protocol SystemAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
}
