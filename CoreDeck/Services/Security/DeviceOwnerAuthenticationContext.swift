import Foundation
import LocalAuthentication

@MainActor
protocol DeviceOwnerAuthenticationContext: AnyObject {
    func canEvaluatePolicy(
        _ policy: LAPolicy,
        error: AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

extension LAContext: DeviceOwnerAuthenticationContext {}
