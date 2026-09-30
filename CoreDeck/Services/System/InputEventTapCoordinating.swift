import Foundation

@MainActor
protocol InputEventTapCoordinating: AnyObject {
    var isTrusted: Bool { get }
    var interruptionHandler: (@MainActor () -> Void)? { get set }

    @discardableResult
    func requestAccessibilityAccess() -> Bool

    @discardableResult
    func setKeyboardBlocking(_ enabled: Bool) -> Bool

    @discardableResult
    func setScrollReversal(_ configuration: ScrollReversalConfiguration) -> Bool

    @discardableResult
    func maintain() -> Bool

    func stopAll()
    func openAccessibilitySettings()
}
