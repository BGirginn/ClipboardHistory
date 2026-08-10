import Foundation
@testable import ClipboardHistory

@MainActor
final class InputEventTapCoordinatorStub: InputEventTapCoordinating {
    var trusted: Bool
    var requestResult = false
    var keyboardResult = true
    var scrollResult = true
    var maintainResult = true
    var interruptionHandler: (@MainActor () -> Void)?
    private(set) var requestCount = 0
    private(set) var keyboardValues: [Bool] = []
    private(set) var scrollConfigurations: [ScrollReversalConfiguration] = []
    private(set) var stopAllCount = 0
    private(set) var openSettingsCount = 0

    init(isTrusted: Bool) {
        trusted = isTrusted
    }

    var isTrusted: Bool { trusted }

    func requestAccessibilityAccess() -> Bool {
        requestCount += 1
        return requestResult
    }

    func setKeyboardBlocking(_ enabled: Bool) -> Bool {
        keyboardValues.append(enabled)
        return keyboardResult
    }

    func setScrollReversal(_ configuration: ScrollReversalConfiguration) -> Bool {
        scrollConfigurations.append(configuration)
        return scrollResult
    }

    func maintain() -> Bool {
        maintainResult
    }

    func stopAll() {
        stopAllCount += 1
    }

    func openAccessibilitySettings() {
        openSettingsCount += 1
    }

    func fireInterruption() {
        interruptionHandler?()
    }
}
