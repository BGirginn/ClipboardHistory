import Foundation
import LocalAuthentication

@MainActor
protocol SystemAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
}

@MainActor
protocol DeviceOwnerAuthenticationContext: AnyObject {
    func canEvaluatePolicy(
        _ policy: LAPolicy,
        error: AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

extension LAContext: DeviceOwnerAuthenticationContext {}

enum SystemAuthenticationError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        }
    }
}

@MainActor
final class LocalSystemAuthenticator: SystemAuthenticating {
    private let contextProvider: @MainActor () -> any DeviceOwnerAuthenticationContext

    static func liveContext() -> any DeviceOwnerAuthenticationContext {
        LAContext()
    }

    init(
        contextProvider: @escaping @MainActor () -> any DeviceOwnerAuthenticationContext = liveContext
    ) {
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
