import XCTest
@testable import ClipboardHistory

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
        let coordinator = makeCoordinator { closeCount += 1 }
        coordinator.menuTrackingDidBegin()

        coordinator.requestCloseForOutsideInteraction()
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(coordinator.hasDeferredClose)

        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        try? await Task.sleep(for: .milliseconds(75))
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
        let coordinator = makeCoordinator { closeCount += 1 }
        coordinator.menuTrackingDidBegin()
        coordinator.menuTrackingDidBegin()
        coordinator.requestCloseForOutsideInteraction()

        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        coordinator.menuTrackingDidEnd()
        XCTAssertEqual(closeCount, 0)
        try? await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(closeCount, 1)
    }

    private func makeCoordinator(close: @escaping () -> Void) -> PanelCloseCoordinator {
        PanelCloseCoordinator(isPanelShown: { true }, closePanel: close)
    }
}
