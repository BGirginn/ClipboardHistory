import CoreGraphics
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class ScrollReversalControllerTests: XCTestCase {
    func testSafeDefaultsAndPersistence() {
        withSettings { settings, defaults in
            let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
            let controller = ScrollReversalController(
                coordinator: coordinator,
                settings: settings
            )

            XCTAssertFalse(controller.isEnabled)
            XCTAssertTrue(controller.reversesDiscreteVertical)
            XCTAssertTrue(controller.reversesDiscreteHorizontal)
            XCTAssertFalse(controller.reversesPreciseVertical)
            XCTAssertFalse(controller.reversesPreciseHorizontal)

            controller.isEnabled = true
            controller.reversesPreciseVertical = true

            let reopened = AppSettings(defaults: defaults)
            XCTAssertTrue(reopened.scrollReversalEnabled)
            XCTAssertTrue(reopened.reversePreciseScrollVertical)
            XCTAssertTrue(controller.isActive)
        }
    }

    func testPermissionDenialFailsOpenAndRetryActivatesWithoutAnotherPrompt() {
        withSettings { settings, _ in
            let coordinator = InputEventTapCoordinatorStub(isTrusted: false)
            let controller = ScrollReversalController(
                coordinator: coordinator,
                settings: settings
            )

            controller.isEnabled = true

            XCTAssertFalse(controller.isActive)
            XCTAssertTrue(controller.permissionRequired)
            XCTAssertEqual(coordinator.requestCount, 1)
            XCTAssertFalse(coordinator.scrollConfigurations.last?.isEnabled ?? true)

            coordinator.trusted = true
            controller.retryAfterPermissionChange()

            XCTAssertTrue(controller.isActive)
            XCTAssertFalse(controller.permissionRequired)
            XCTAssertEqual(coordinator.requestCount, 1)
        }
    }

    func testDiscreteAndPreciseAxesAreTransformedIndependently() throws {
        let lineEvent = try makeScrollEvent(continuous: false)
        let preciseEvent = try makeScrollEvent(continuous: true)
        let configuration = ScrollReversalConfiguration(
            isEnabled: true,
            reversesDiscreteVertical: true,
            reversesDiscreteHorizontal: false,
            reversesPreciseVertical: false,
            reversesPreciseHorizontal: true
        )
        let tapConfiguration = InputEventTapConfiguration(scrollReversal: configuration)
        let lineBefore = axisValues(lineEvent)
        let preciseBefore = axisValues(preciseEvent)

        _ = SystemInputEventTapCoordinator.filterEvent(
            type: .scrollWheel,
            event: lineEvent,
            configuration: tapConfiguration
        )
        _ = SystemInputEventTapCoordinator.filterEvent(
            type: .scrollWheel,
            event: preciseEvent,
            configuration: tapConfiguration
        )

        assertAxis(lineEvent, axis: 1, equals: lineBefore[0].negated)
        assertAxis(lineEvent, axis: 2, equals: lineBefore[1])
        assertAxis(preciseEvent, axis: 1, equals: preciseBefore[0])
        assertAxis(preciseEvent, axis: 2, equals: preciseBefore[1].negated)
        XCTAssertEqual(lineEvent.getIntegerValueField(.scrollWheelEventScrollPhase), 4)
        XCTAssertEqual(lineEvent.getIntegerValueField(.scrollWheelEventMomentumPhase), 8)
    }

    func testEveryDeltaRepresentationIsReversedAndNonScrollEventIsUntouched() throws {
        let event = try makeScrollEvent(continuous: false)
        let timestamp = event.timestamp
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let configuration = InputEventTapConfiguration(
            scrollReversal: ScrollReversalConfiguration(
                isEnabled: true,
                reversesDiscreteVertical: true,
                reversesDiscreteHorizontal: true,
                reversesPreciseVertical: false,
                reversesPreciseHorizontal: false
            )
        )

        _ = SystemInputEventTapCoordinator.filterEvent(
            type: .scrollWheel,
            event: event,
            configuration: configuration
        )

        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -3)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1), -1.5)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventRawDeltaAxis1), -2.5)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), -2)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis2), -0.75)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventRawDeltaAxis2), -1.25)
        XCTAssertEqual(event.timestamp, timestamp)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUnixProcessID), sourcePID)

        let mouseEvent = try XCTUnwrap(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
        XCTAssertNotNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .mouseMoved,
                event: mouseEvent,
                configuration: configuration
            )
        )
    }

    func testSharedInterruptionMarksKeyboardAndScrollInactive() async {
        let suite = "ScrollInterruption-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ScrollInterruption-\(UUID().uuidString)"
        )
        let settings = AppSettings(defaults: defaults)
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let keyboard = KeyboardCleaningController(coordinator: coordinator)
        let scroll = ScrollReversalController(coordinator: coordinator, settings: settings)
        let storage = StorageService(baseDirectory: directory)
        let appModel = AppModel(
            storage: storage,
            settings: settings,
            inputEventTapCoordinator: coordinator,
            keyboardCleaningController: keyboard,
            scrollReversalController: scroll,
            startsAutomatically: false
        )

        keyboard.start()
        scroll.isEnabled = true
        coordinator.fireInterruption()

        XCTAssertFalse(keyboard.isActive)
        XCTAssertFalse(scroll.isActive)
        XCTAssertNotNil(keyboard.errorMessage)
        XCTAssertNotNil(scroll.errorMessage)
        appModel.prepareForShutdown()
        await storage.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCombinedConfigurationBlocksKeysAndStillReversesScroll() throws {
        let keyEvent = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        )
        let scrollEvent = try makeScrollEvent(continuous: false)
        let before = axisValues(scrollEvent)[0]
        let configuration = InputEventTapConfiguration(
            blocksKeyboard: true,
            scrollReversal: ScrollReversalConfiguration(
                isEnabled: true,
                reversesDiscreteVertical: true,
                reversesDiscreteHorizontal: false,
                reversesPreciseVertical: false,
                reversesPreciseHorizontal: false
            )
        )

        XCTAssertNil(
            SystemInputEventTapCoordinator.filterEvent(
                type: .keyDown,
                event: keyEvent,
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
        assertAxis(scrollEvent, axis: 1, equals: before.negated)
    }

    func testPermissionRevocationFailsOpenAndIntegerOverflowIsSaturated() {
        withSettings { settings, _ in
            let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
            let controller = ScrollReversalController(
                coordinator: coordinator,
                settings: settings
            )
            controller.isEnabled = true
            XCTAssertTrue(controller.isActive)

            coordinator.trusted = false
            controller.refreshAfterWake()

            XCTAssertFalse(controller.isActive)
            XCTAssertTrue(controller.permissionRequired)
            XCTAssertFalse(coordinator.scrollConfigurations.last?.isEnabled ?? true)
        }
        XCTAssertEqual(SystemInputEventTapCoordinator.reversedScrollInteger(.min), .max)
        XCTAssertEqual(SystemInputEventTapCoordinator.reversedScrollInteger(.max), -.max)
        XCTAssertEqual(SystemInputEventTapCoordinator.reversedScrollInteger(0), 0)
    }

    private func makeScrollEvent(continuous: Bool) throws -> CGEvent {
        let event = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: 3,
                wheel2: 2,
                wheel3: 0
            )
        )
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 8)
        event.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: 1.5)
        event.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: 2.5)
        event.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis2, value: 0.75)
        event.setDoubleValueField(.scrollWheelEventRawDeltaAxis2, value: 1.25)
        return event
    }

    private struct AxisValues: Equatable {
        let delta: Int64
        let point: Int64

        var negated: AxisValues {
            AxisValues(delta: -delta, point: -point)
        }
    }

    private func axisValues(_ event: CGEvent) -> [AxisValues] {
        [
            AxisValues(
                delta: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            ),
            AxisValues(
                delta: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            )
        ]
    }

    private func assertAxis(_ event: CGEvent, axis: Int, equals expected: AxisValues) {
        let delta: CGEventField = axis == 1
            ? .scrollWheelEventDeltaAxis1
            : .scrollWheelEventDeltaAxis2
        let point: CGEventField = axis == 1
            ? .scrollWheelEventPointDeltaAxis1
            : .scrollWheelEventPointDeltaAxis2
        XCTAssertEqual(event.getIntegerValueField(delta), expected.delta)
        XCTAssertEqual(event.getIntegerValueField(point), expected.point)
    }

    private func withSettings(_ body: (AppSettings, UserDefaults) -> Void) {
        let suite = "ScrollReversalSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(AppSettings(defaults: defaults), defaults)
    }
}
