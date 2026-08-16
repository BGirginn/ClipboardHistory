import AppKit
import ApplicationServices
import Carbon
@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class SystemInputEventTapCoordinator: InputEventTapCoordinating {
    private let accessibilityAuthorization: any AccessibilityAuthorizing
    private let secureInputEvaluator: () -> Bool
    private let accessibilitySettingsOpener: (URL) -> Void
    private var configuration = InputEventTapConfiguration()
    // Core Foundation run-loop handles are created and consumed on the main actor.
    // Unsafe isolation is limited to deterministic cleanup from nonisolated deinit.
    private nonisolated(unsafe) var eventTap: CFMachPort?
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?

    var interruptionHandler: (@MainActor () -> Void)?

    init(
        accessibilityAuthorization: (any AccessibilityAuthorizing)? = nil,
        promptedTrustEvaluator: @escaping (CFDictionary) -> Bool = AXIsProcessTrustedWithOptions,
        trustEvaluator: @escaping () -> Bool = AXIsProcessTrusted,
        secureInputEvaluator: @escaping () -> Bool = IsSecureEventInputEnabled,
        accessibilitySettingsOpener: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.accessibilityAuthorization = accessibilityAuthorization
            ?? SystemAccessibilityAuthorization(
                promptedTrustEvaluator: promptedTrustEvaluator,
                trustEvaluator: trustEvaluator
            )
        self.secureInputEvaluator = secureInputEvaluator
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
    }

    var isTrusted: Bool {
        accessibilityAuthorization.isTrusted
    }

    func requestAccessibilityAccess() -> Bool {
        accessibilityAuthorization.requestAccessIfNeeded()
    }

    func setKeyboardBlocking(_ enabled: Bool) -> Bool {
        guard !enabled || !secureInputEvaluator() else { return false }
        var updated = configuration
        updated.blocksKeyboard = enabled
        return apply(updated)
    }

    func setScrollReversal(_ scrollConfiguration: ScrollReversalConfiguration) -> Bool {
        var updated = configuration
        updated.scrollReversal = scrollConfiguration
        return apply(updated)
    }

    func maintain() -> Bool {
        guard !configuration.isEmpty else { return true }
        if configuration.blocksKeyboard, secureInputEvaluator() {
            handleUnrecoverableInterruption()
            return false
        }
        guard let eventTap else { return false }
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func stopAll() {
        configuration = InputEventTapConfiguration()
        tearDownTap()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        accessibilitySettingsOpener(url)
    }

    private func apply(_ updated: InputEventTapConfiguration) -> Bool {
        guard updated != configuration || !maintain() else { return true }
        let wasActive = !configuration.isEmpty
        tearDownTap()
        configuration = updated
        guard !updated.isEmpty else { return true }
        guard isTrusted, installTap(for: updated) else {
            configuration = InputEventTapConfiguration()
            tearDownTap()
            if wasActive {
                interruptionHandler?()
            }
            return false
        }
        return true
    }

    private func installTap(for configuration: InputEventTapConfiguration) -> Bool {
        let eventMask = Self.eventMask(for: configuration)
        guard eventMask != 0,
              let eventTap = CGEvent.tapCreate(
                  tap: .cgSessionEventTap,
                  place: .headInsertEventTap,
                  options: .defaultTap,
                  eventsOfInterest: eventMask,
                  callback: Self.eventTapCallback,
                  userInfo: Unmanaged.passUnretained(self).toOpaque()
              ) else { return false }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    private func tearDownTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    static func eventMask(for configuration: InputEventTapConfiguration) -> CGEventMask {
        var mask = CGEventMask(0)
        if configuration.blocksKeyboard {
            for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
                mask |= CGEventMask(1) << type.rawValue
            }
            mask |= CGEventMask(1) << 14
        }
        if configuration.scrollReversal.hasActiveAxis {
            mask |= CGEventMask(1) << CGEventType.scrollWheel.rawValue
        }
        return mask
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let coordinator = Unmanaged<SystemInputEventTapCoordinator>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return MainActor.assumeIsolated {
            coordinator.filter(type: type, event: event)
        }
    }

    func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard let eventTap else {
                handleUnrecoverableInterruption()
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                handleUnrecoverableInterruption()
            }
            return Unmanaged.passUnretained(event)
        }

        return Self.filterEvent(type: type, event: event, configuration: configuration)
    }

    nonisolated static func filterEvent(
        type: CGEventType,
        event: CGEvent,
        configuration: InputEventTapConfiguration
    ) -> Unmanaged<CGEvent>? {
        if configuration.blocksKeyboard {
            if type.rawValue == 14 {
                return nil
            }
            switch type {
            case .keyDown, .keyUp, .flagsChanged:
                return nil
            default:
                break
            }
        }

        if type == .scrollWheel, configuration.scrollReversal.hasActiveAxis {
            reverseScrollEvent(event, configuration: configuration.scrollReversal)
        }
        return Unmanaged.passUnretained(event)
    }

    private nonisolated static func reverseScrollEvent(
        _ event: CGEvent,
        configuration: ScrollReversalConfiguration
    ) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if configuration.reversesVertical(isContinuous: isContinuous) {
            reverseAxis(
                event,
                integerFields: [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1],
                doubleFields: [
                    .scrollWheelEventFixedPtDeltaAxis1,
                    .scrollWheelEventAcceleratedDeltaAxis1,
                    .scrollWheelEventRawDeltaAxis1
                ]
            )
        }
        if configuration.reversesHorizontal(isContinuous: isContinuous) {
            reverseAxis(
                event,
                integerFields: [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2],
                doubleFields: [
                    .scrollWheelEventFixedPtDeltaAxis2,
                    .scrollWheelEventAcceleratedDeltaAxis2,
                    .scrollWheelEventRawDeltaAxis2
                ]
            )
        }
    }

    private nonisolated static func reverseAxis(
        _ event: CGEvent,
        integerFields: [CGEventField],
        doubleFields: [CGEventField]
    ) {
        // CGEvent's line, point and fixed-point deltas are coupled internally.
        // Capture every representation before writing any of them so later
        // setters cannot cause a second inversion of an already-updated field.
        let integerValues = integerFields.map { field in
            (field, event.getIntegerValueField(field))
        }
        let doubleValues = doubleFields.map { field in
            (field, event.getDoubleValueField(field))
        }
        for (field, value) in integerValues {
            let reversed = Self.reversedScrollInteger(value)
            event.setIntegerValueField(field, value: reversed)
        }
        for (field, value) in doubleValues {
            if value.isFinite {
                event.setDoubleValueField(field, value: -value)
            }
        }
    }

    nonisolated static func reversedScrollInteger(_ value: Int64) -> Int64 {
        value == .min ? .max : -value
    }

    func handleUnrecoverableInterruption() {
        configuration = InputEventTapConfiguration()
        tearDownTap()
        interruptionHandler?()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
}
