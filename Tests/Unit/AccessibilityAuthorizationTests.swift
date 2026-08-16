import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class AccessibilityAuthorizationTests: XCTestCase {
    func testSharedAuthorizationPromptsOnlyOncePerSessionAcrossFeatures() {
        var promptCount = 0
        var isTrusted = false
        let authorization = SystemAccessibilityAuthorization(
            promptedTrustEvaluator: { _ in
                promptCount += 1
                return false
            },
            trustEvaluator: { isTrusted }
        )
        let pasteBackend = SystemAccessibilityPasteBackend(
            accessibilityAuthorization: authorization
        )
        let inputCoordinator = SystemInputEventTapCoordinator(
            accessibilityAuthorization: authorization
        )

        XCTAssertFalse(pasteBackend.isTrusted(prompt: true))
        XCTAssertFalse(inputCoordinator.requestAccessibilityAccess())
        XCTAssertFalse(pasteBackend.isTrusted(prompt: true))
        XCTAssertEqual(promptCount, 1)

        isTrusted = true
        XCTAssertTrue(inputCoordinator.requestAccessibilityAccess())
        XCTAssertTrue(pasteBackend.isTrusted(prompt: false))
        XCTAssertEqual(promptCount, 1)
    }
}
