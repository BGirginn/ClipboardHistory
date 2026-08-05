import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class AccessibilityPasteServiceTests: XCTestCase {
    func testSystemBackendSafeRuntimeBoundaries() async {
        let backend = SystemAccessibilityPasteBackend()
        _ = backend.frontmostProcessIdentifier
        _ = backend.isTrusted(prompt: false)
        let currentProcess = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(backend.isProcessAvailable(currentProcess))
        XCTAssertFalse(backend.isProcessAvailable(999_999))
        backend.activate(999_999)
        backend.activate(currentProcess)
        await backend.waitBeforePosting()
        XCTAssertTrue(backend.postCommandV(to: 999_999))
    }

    func testPermissionRequestIsDeferredUntilPaste() async {
        let backend = StubAccessibilityPasteBackend()
        backend.frontmostProcessIdentifier = 42
        backend.isTrusted = false
        let service = AccessibilityPasteService(backend: backend)

        service.captureTargetApplication()
        let result = await service.paste()

        XCTAssertEqual(result, .permissionRequired)
        XCTAssertEqual(backend.promptValues, [false, true])
        XCTAssertTrue(backend.activatedProcessIdentifiers.isEmpty)
    }

    func testMissingOrUnavailableTargetDoesNotPostAnEvent() async {
        let backend = StubAccessibilityPasteBackend()
        let service = AccessibilityPasteService(backend: backend)

        let missingTargetResult = await service.paste()
        XCTAssertEqual(missingTargetResult, .targetUnavailable)
        backend.frontmostProcessIdentifier = 42
        backend.isProcessAvailable = false
        service.captureTargetApplication()
        let unavailableTargetResult = await service.paste()
        XCTAssertEqual(unavailableTargetResult, .targetUnavailable)
        XCTAssertTrue(backend.postedProcessIdentifiers.isEmpty)
    }

    func testCurrentProcessIsNotCaptured() async {
        let backend = StubAccessibilityPasteBackend()
        backend.frontmostProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let service = AccessibilityPasteService(backend: backend)

        service.captureTargetApplication()

        let result = await service.paste()
        XCTAssertEqual(result, .targetUnavailable)
    }

    func testEventFailureAndSuccessfulPasteAreReported() async {
        let backend = StubAccessibilityPasteBackend()
        backend.frontmostProcessIdentifier = 42
        backend.canPostEvent = false
        let service = AccessibilityPasteService(backend: backend)
        service.captureTargetApplication()

        let failedResult = await service.paste()
        XCTAssertEqual(failedResult, .eventCreationFailed)
        XCTAssertEqual(backend.activatedProcessIdentifiers, [42])
        XCTAssertEqual(backend.waitCount, 1)

        backend.canPostEvent = true
        let pastedResult = await service.paste()
        XCTAssertEqual(pastedResult, .pasted)
        XCTAssertEqual(backend.postedProcessIdentifiers, [42, 42])
    }
}

@MainActor
private final class StubAccessibilityPasteBackend: AccessibilityPasteBackend {
    var frontmostProcessIdentifier: pid_t?
    var isTrusted = true
    var isProcessAvailable = true
    var canPostEvent = true
    var promptValues: [Bool] = []
    var activatedProcessIdentifiers: [pid_t] = []
    var postedProcessIdentifiers: [pid_t] = []
    var waitCount = 0

    func isTrusted(prompt: Bool) -> Bool {
        promptValues.append(prompt)
        return isTrusted
    }

    func isProcessAvailable(_ processIdentifier: pid_t) -> Bool {
        isProcessAvailable
    }

    func activate(_ processIdentifier: pid_t) {
        activatedProcessIdentifiers.append(processIdentifier)
    }

    func waitBeforePosting() async {
        waitCount += 1
    }

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        postedProcessIdentifiers.append(processIdentifier)
        return canPostEvent
    }
}
