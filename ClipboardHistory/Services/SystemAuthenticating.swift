import Foundation
import LocalAuthentication

@MainActor
protocol SystemAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
}

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
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
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
