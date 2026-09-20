import XCTest
@testable import ClipboardHistoryTestHost

@MainActor
final class PanelCloseCoordinatorTests: XCTestCase {
    func testOutsideInteractionClosesImmediatelyWithoutMenu() {
        var closeCount = 0
        let coordinator = makeCoordinator { closeCount += 1 }

        coordinator.requestCloseForOutsideInteraction()

        XCTAssertEqual(closeCount, 1)
    }

    func testOutsideInteractionDefersUntilMenuTrackingEnds() async {
        var closeCount = 0
        let didClose = expectation(description: "panel closes after menu tracking")
        let coordinator = makeCoordinator {
            closeCount += 1
            didClose.fulfill()
        }
        coordinator.menuTrackingDidBegin()

        coordinator.requestCloseForOutsideInteraction()
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(coordinator.hasDeferredClose)

        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        await fulfillment(of: [didClose], timeout: 2)
        XCTAssertEqual(closeCount, 1)
    }

    func testMenuCommandCancelsDeferredCloseAndKeepsPanelOpen() {
        var closeCount = 0
        let coordinator = makeCoordinator { closeCount += 1 }
        coordinator.menuTrackingDidBegin()
        coordinator.requestCloseForOutsideInteraction()

        coordinator.menuCommandDidRun()
        coordinator.menuTrackingDidEnd()

        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(coordinator.hasDeferredClose)
    }

    func testMenuCommandDeliveredAfterTrackingEndCancelsScheduledClose() async {
        var closeCount = 0
        let coordinator = makeCoordinator { closeCount += 1 }
        coordinator.menuTrackingDidBegin()
        coordinator.requestCloseForOutsideInteraction()
        coordinator.menuTrackingDidEnd()

        coordinator.menuCommandDidRun()
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertEqual(closeCount, 0)
    }

    func testNestedMenuTrackingClosesOnlyAfterOutermostMenuEnds() async {
        var closeCount = 0
        let didClose = expectation(description: "panel closes after the outermost menu")
        let coordinator = makeCoordinator {
            closeCount += 1
            didClose.fulfill()
        }
        coordinator.menuTrackingDidBegin()
        coordinator.menuTrackingDidBegin()
        coordinator.requestCloseForOutsideInteraction()

        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        await fulfillment(of: [didClose], timeout: 2)
        XCTAssertEqual(closeCount, 1)
    }

    private func makeCoordinator(close: @escaping () -> Void) -> PanelCloseCoordinator {
        PanelCloseCoordinator(isPanelShown: { true }, closePanel: close)
    }
}
