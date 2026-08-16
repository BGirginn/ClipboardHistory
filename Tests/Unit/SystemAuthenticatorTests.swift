import Foundation
import LocalAuthentication
import XCTest
@testable import ClipboardHistory

@MainActor
final class SystemAuthenticatorTests: XCTestCase {
    func testLocalSystemAuthenticatorCoversSuccessCancellationAndUnavailableReasons() async throws {
        _ = LocalSystemAuthenticator()
        _ = LocalSystemAuthenticator.liveContext()
        let successContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: true,
            evaluationResult: .success(true)
        )
        let success = LocalSystemAuthenticator(contextProvider: { successContext })
        let didAuthenticate = try await success.authenticate(reason: "Unlock in test")
        XCTAssertTrue(didAuthenticate)
        XCTAssertEqual(successContext.reasons, ["Unlock in test"])
        XCTAssertEqual(
            successContext.policies,
            [.deviceOwnerAuthentication, .deviceOwnerAuthentication]
        )

        let cancellationContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: true,
            evaluationResult: .success(false)
        )
        let cancellation = LocalSystemAuthenticator(contextProvider: { cancellationContext })
        let didCancel = try await cancellation.authenticate(reason: "Cancel in test")
        XCTAssertFalse(didCancel)

        let explicitErrorContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: false,
            canEvaluateError: NSError(domain: LAError.errorDomain, code: LAError.biometryNotAvailable.rawValue),
            evaluationResult: .success(false)
        )
        let explicitError = LocalSystemAuthenticator(contextProvider: { explicitErrorContext })
        await XCTAssertThrowsErrorAsync(try await explicitError.authenticate(reason: "Unavailable")) {
            XCTAssertNotNil(($0 as? SystemAuthenticationError)?.errorDescription)
        }

        let fallbackContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: false,
            evaluationResult: .success(false)
        )
        let fallback = LocalSystemAuthenticator(contextProvider: { fallbackContext })
        await XCTAssertThrowsErrorAsync(try await fallback.authenticate(reason: "Unavailable")) {
            XCTAssertEqual(
                ($0 as? SystemAuthenticationError)?.errorDescription,
                "System authentication is unavailable."
            )
        }
    }
}

private final class StubDeviceOwnerAuthenticationContext: DeviceOwnerAuthenticationContext {
    let canEvaluate: Bool
    let canEvaluateError: Error?
    let evaluationResult: Result<Bool, Error>
    private(set) var policies: [LAPolicy] = []
    private(set) var reasons: [String] = []

    init(
        canEvaluate: Bool,
        canEvaluateError: Error? = nil,
        evaluationResult: Result<Bool, Error>
    ) {
        self.canEvaluate = canEvaluate
        self.canEvaluateError = canEvaluateError
        self.evaluationResult = evaluationResult
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        policies.append(policy)
        if let canEvaluateError {
            error?.pointee = canEvaluateError as NSError
        }
        return canEvaluate
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        policies.append(policy)
        reasons.append(localizedReason)
        return try evaluationResult.get()
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
