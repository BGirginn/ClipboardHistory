import Foundation
import LocalAuthentication

@MainActor
final class LocalSystemAuthenticator: SystemAuthenticating {
    private let contextProvider: @MainActor () -> any DeviceOwnerAuthenticationContext

    static func liveContext() -> any DeviceOwnerAuthenticationContext {
        LAContext()
    }

    convenience init() {
        self.init(contextProvider: Self.liveContext)
    }

    init(contextProvider: @escaping @MainActor () -> any DeviceOwnerAuthenticationContext) {
        self.contextProvider = contextProvider
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = contextProvider()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &evaluationError
        ) else {
            throw SystemAuthenticationError.unavailable(
                evaluationError?.localizedDescription
                    ?? String(localized: "System authentication is unavailable.")
            )
        }
        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
    }
}
