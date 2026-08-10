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

    func testPreparedNativeMenuIgnoresInitialResignAndSelectedCommandKeepsPanelOpen() async {
        let harness = Harness()
        harness.start()
        harness.coordinator.prepareForPanelMenu()

        harness.notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        harness.coordinator.requestCloseForOutsideInteraction()
        XCTAssertTrue(harness.isPanelShown)
        harness.notificationCenter.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        harness.coordinator.requestCloseForOutsideInteraction()
        harness.coordinator.menuCommandDidRun()
        harness.notificationCenter.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertTrue(harness.isPanelShown)
        XCTAssertEqual(harness.closeCount, 0)
        harness.stop()
    }

    func testModalInteractionDefersEveryOutsideCloseUntilCompletion() {
        let harness = Harness()
        harness.start()
        harness.coordinator.beginModalInteraction()

        harness.notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        harness.coordinator.requestCloseForOutsideInteraction()

        XCTAssertTrue(harness.isPanelShown)
        XCTAssertTrue(harness.coordinator.hasDeferredClose)
        harness.coordinator.endModalInteraction()
        XCTAssertTrue(harness.isPanelShown)
        XCTAssertFalse(harness.coordinator.hasDeferredClose)
        harness.stop()
    }

    func testPanelRightClickBeforeMenuTrackingIgnoresTransientApplicationResign() async throws {
        let notificationCenter = NotificationCenter()
        let monitor = RecordingPanelEventMonitor()
        var isShown = true
        var closeCount = 0
        let coordinator = PanelCloseCoordinator(
            notificationCenter: notificationCenter,
            eventMonitor: monitor,
            isPanelShown: { isShown },
            isPanelEvent: { _ in true },
            closePanel: {
                isShown = false
                closeCount += 1
            }
        )
        coordinator.start()
        let rightClick = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        XCTAssertTrue(monitor.fireLocal(rightClick) === rightClick)
        notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        notificationCenter.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        notificationCenter.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        try? await Task.sleep(for: .milliseconds(75))

        XCTAssertTrue(isShown)
        XCTAssertEqual(closeCount, 0)
        coordinator.stop()
    }

    func testPanelRightClickGraceExpiresWhenNoMenuStarts() async throws {
        let notificationCenter = NotificationCenter()
        let monitor = RecordingPanelEventMonitor()
        var closeCount = 0
        let coordinator = PanelCloseCoordinator(
            notificationCenter: notificationCenter,
            eventMonitor: monitor,
            isPanelShown: { true },
            isPanelEvent: { _ in true },
            closePanel: { closeCount += 1 }
        )
        coordinator.start()
        let rightClick = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        _ = monitor.fireLocal(rightClick)
        XCTAssertTrue(coordinator.isPanelContextMenuInteraction)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(coordinator.isPanelContextMenuInteraction)
        notificationCenter.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        XCTAssertEqual(closeCount, 1)
        coordinator.stop()
    }

    func testInjectedGlobalAndLocalMonitorsCloseAndAreRemoved() async throws {
        let monitor = RecordingPanelEventMonitor()
        var isShown = true
        var closeCount = 0
        let coordinator = PanelCloseCoordinator(
            notificationCenter: NotificationCenter(),
            eventMonitor: monitor,
            isPanelShown: { isShown },
            closePanel: {
                isShown = false
                closeCount += 1
            }
        )
        coordinator.start()
        coordinator.start()
        let event = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )
        )

        XCTAssertTrue(monitor.fireLocal(event) === event)
        XCTAssertEqual(closeCount, 1)
        isShown = true
        monitor.fireGlobal(event)
        for _ in 0..<20 where closeCount < 2 { await Task.yield() }
        XCTAssertEqual(closeCount, 2)

        coordinator.stop()
        coordinator.stop()
        XCTAssertEqual(monitor.removedCount, 2)
    }

    func testLocalPanelAndStatusEventsAreIgnoredAndHiddenPanelCancelsDeferredClose() async throws {
        let monitor = RecordingPanelEventMonitor()
        var isShown = true
        var panelEvent = true
        var statusEvent = false
        var closeCount = 0
        let coordinator = PanelCloseCoordinator(
            notificationCenter: NotificationCenter(),
            eventMonitor: monitor,
            isPanelShown: { isShown },
            isPanelEvent: { _ in panelEvent },
            isStatusItemEvent: { _ in statusEvent },
            closePanel: { closeCount += 1 }
        )
        coordinator.start()
        let event = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )
        )
        _ = monitor.fireLocal(event)
        panelEvent = false
        statusEvent = true
        _ = monitor.fireLocal(event)
        XCTAssertEqual(closeCount, 0)

        statusEvent = false
        coordinator.menuTrackingDidBegin()
        coordinator.requestCloseForOutsideInteraction()
        coordinator.menuTrackingDidEnd()
        isShown = false
        try? await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(coordinator.menuCommandWasSelected)
        coordinator.stop()
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

@MainActor
private final class RecordingPanelEventMonitor: PanelEventMonitoring {
    private var globalHandler: ((NSEvent) -> Void)?
    private var localHandler: ((NSEvent) -> NSEvent?)?
    private(set) var removedCount = 0

    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? {
        globalHandler = handler
        return NSObject()
    }

    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localHandler = handler
        return NSObject()
    }

    func removeMonitor(_ monitor: Any) {
        removedCount += 1
    }

    func fireGlobal(_ event: NSEvent) {
        globalHandler?(event)
    }

    func fireLocal(_ event: NSEvent) -> NSEvent? {
        localHandler?(event)
    }
}
