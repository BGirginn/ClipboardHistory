import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class PanelCloseCoordinatorIntegrationTests: XCTestCase {
    func testApplicationResignNotificationClosesPanel() {
        let harness = Harness()
        harness.start()

        harness.notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertFalse(harness.isPanelShown)
        XCTAssertEqual(harness.closeCount, 1)
        harness.stop()
    }

    func testMenuNotificationsDeferApplicationResignAndLateCommandKeepsPanelOpen() async {
        let harness = Harness()
        harness.start()
        harness.notificationCenter.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        harness.notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertTrue(harness.isPanelShown)
        XCTAssertEqual(harness.closeCount, 0)

        harness.notificationCenter.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        harness.coordinator.menuCommandDidRun()
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertTrue(harness.isPanelShown)
        XCTAssertEqual(harness.closeCount, 0)
        harness.stop()
    }

    func testMenuNotificationsDeliverDeferredCloseAfterTrackingEnds() async {
        let harness = Harness()
        harness.start()
        harness.notificationCenter.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        harness.notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertTrue(harness.isPanelShown)
        harness.notificationCenter.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        XCTAssertTrue(harness.isPanelShown)
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertFalse(harness.isPanelShown)
        XCTAssertEqual(harness.closeCount, 1)
        harness.stop()
    }

    @MainActor
    private final class Harness {
        let notificationCenter = NotificationCenter()
        private(set) var isPanelShown = true
        private(set) var closeCount = 0
        var coordinator: PanelCloseCoordinator!

        init() {
            coordinator = PanelCloseCoordinator(
                notificationCenter: notificationCenter,
                eventMonitor: IntegrationPanelEventMonitorStub(),
                isPanelShown: { [weak self] in self?.isPanelShown == true },
                closePanel: { [weak self] in
                    self?.isPanelShown = false
                    self?.closeCount += 1
                }
            )
        }

        func start() {
            coordinator.start()
        }

        func stop() {
            coordinator.stop()
        }
    }
}

@MainActor
private final class IntegrationPanelEventMonitorStub: PanelEventMonitoring {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { nil }
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    func removeMonitor(_ monitor: Any) {}
}
