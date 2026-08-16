import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class KeyboardCleaningControllerTests: XCTestCase {
    func testEventFilterDropsKeyboardAndMediaButPreservesMouseAndScrollInput() throws {
        let keyEvent = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        )
        let mouseEvent = try XCTUnwrap(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
        let scrollEvent = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: 1,
                wheel2: 0,
                wheel3: 0
            )
        )
        let mediaType = try XCTUnwrap(CGEventType(rawValue: 14))
        let configuration = InputEventTapConfiguration(blocksKeyboard: true)

        XCTAssertNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .keyDown,
                event: keyEvent,
                configuration: configuration
            )
        )
        XCTAssertNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .keyUp,
                event: keyEvent,
                configuration: configuration
            )
        )
        XCTAssertNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .flagsChanged,
                event: keyEvent,
                configuration: configuration
            )
        )
        XCTAssertNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: mediaType,
                event: keyEvent,
                configuration: configuration
            )
        )
        XCTAssertNotNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .mouseMoved,
                event: mouseEvent,
                configuration: configuration
            )
        )
        XCTAssertNotNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .scrollWheel,
                event: scrollEvent,
                configuration: configuration
            )
        )
        XCTAssertEqual(scrollEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
    }

    func testMissingPermissionPromptsAndKeepsKeyboardAvailable() {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: false)
        coordinator.requestResult = false
        let controller = KeyboardCleaningController(coordinator: coordinator)

        controller.start()

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.permissionRequired)
        XCTAssertEqual(coordinator.requestCount, 1)
        XCTAssertEqual(coordinator.keyboardValues, [])

        controller.openAccessibilitySettings()
        XCTAssertEqual(coordinator.openSettingsCount, 1)
    }

    func testStartAndManualStopControlEventTap() {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let scheduler = KeyboardCleaningTimerSchedulerStub()
        var currentDate = Date(timeIntervalSince1970: 100)
        let controller = KeyboardCleaningController(
            coordinator: coordinator,
            timerScheduler: scheduler,
            duration: 3,
            now: { currentDate }
        )

        controller.start()

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.remainingSeconds, 3)
        XCTAssertEqual(coordinator.keyboardValues, [true])
        XCTAssertEqual(scheduler.scheduleCount, 1)

        currentDate = currentDate.addingTimeInterval(1.2)
        scheduler.fire()
        XCTAssertEqual(controller.remainingSeconds, 2)

        controller.stop()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.remainingSeconds, 3)
        XCTAssertEqual(coordinator.keyboardValues, [true, false])
        XCTAssertEqual(scheduler.cancelCount, 1)

        controller.stop()
        XCTAssertEqual(coordinator.keyboardValues, [true, false])
    }

    func testCountdownAutomaticallyStopsAtSafetyDeadline() {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let scheduler = KeyboardCleaningTimerSchedulerStub()
        var currentDate = Date(timeIntervalSince1970: 200)
        let controller = KeyboardCleaningController(
            coordinator: coordinator,
            timerScheduler: scheduler,
            duration: 2,
            now: { currentDate }
        )

        controller.start()
        currentDate = currentDate.addingTimeInterval(2)
        scheduler.fire()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(coordinator.keyboardValues, [true, false])
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testUnexpectedEventTapDisableStopsModeAndShowsError() {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let scheduler = KeyboardCleaningTimerSchedulerStub()
        let controller = KeyboardCleaningController(
            coordinator: coordinator,
            timerScheduler: scheduler
        )

        controller.start()
        coordinator.maintainResult = false
        scheduler.fire()

        XCTAssertFalse(controller.isActive)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(coordinator.keyboardValues, [true, false])
    }

    func testEventTapCreationFailureIsVisibleAndModeStaysInactive() {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        coordinator.keyboardResult = false
        let controller = KeyboardCleaningController(coordinator: coordinator)

        controller.start()

        XCTAssertFalse(controller.isActive)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.permissionRequired)
    }

    func testSecureInputFailsOpenInsteadOfReportingKeyboardBlocked() {
        let coordinator = SystemInputEventTapCoordinator(
            promptedTrustEvaluator: { _ in true },
            trustEvaluator: { true },
            secureInputEvaluator: { true }
        )
        let controller = KeyboardCleaningController(coordinator: coordinator)

        controller.start()

        XCTAssertFalse(controller.isActive)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.permissionRequired)
    }

    func testShutdownPreparationAlwaysReleasesKeyboard() async {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let controller = KeyboardCleaningController(coordinator: coordinator)
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "KeyboardCleaningControllerTests-\(UUID().uuidString)"
        )
        let suite = "KeyboardCleaningControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let storage = StorageService(baseDirectory: directory)
        let appModel = AppModel(
            storage: storage,
            settings: AppSettings(defaults: defaults),
            inputEventTapCoordinator: coordinator,
            keyboardCleaningController: controller,
            startsAutomatically: false
        )

        appModel.inputTools.scrollReversal.isEnabled = true
        controller.start()
        appModel.prepareForShutdown()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(coordinator.keyboardValues, [true, false])
        await storage.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    func testSleepAndSessionResignReleaseKeyboardWhileWakeReappliesScrollPreference() async {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let suite = "InputLifecycle-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "InputLifecycle-\(UUID().uuidString)"
        )
        let settings = AppSettings(defaults: defaults)
        let storage = StorageService(baseDirectory: directory)
        let appModel = AppModel(
            storage: storage,
            settings: settings,
            inputEventTapCoordinator: coordinator,
            startsAutomatically: false
        )

        appModel.inputTools.scrollReversal.isEnabled = true
        appModel.inputTools.keyboardCleaning.start()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertFalse(appModel.inputTools.keyboardCleaning.isActive)
        XCTAssertTrue(appModel.inputTools.scrollReversal.isActive)

        let beforeWake = coordinator.scrollConfigurations.count
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertGreaterThan(coordinator.scrollConfigurations.count, beforeWake)
        XCTAssertTrue(appModel.inputTools.scrollReversal.isActive)

        appModel.inputTools.keyboardCleaning.start()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        XCTAssertFalse(appModel.inputTools.keyboardCleaning.isActive)
        XCTAssertTrue(appModel.inputTools.scrollReversal.isActive)

        appModel.prepareForShutdown()
        await storage.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class KeyboardCleaningTimerSchedulerStub: RepeatingTimerScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any RepeatingTimerToken {
        _ = interval
        _ = tolerance
        scheduleCount += 1
        self.action = action
        return KeyboardCleaningTimerTokenStub { [weak self] in
            self?.cancelCount += 1
        }
    }

    func fire() {
        action?()
    }
}

private final class KeyboardCleaningTimerTokenStub: RepeatingTimerToken, @unchecked Sendable {
    private let cancellation: @MainActor () -> Void

    init(cancellation: @escaping @MainActor () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        MainActor.assumeIsolated {
            cancellation()
        }
    }
}
