import Foundation

@MainActor
protocol AccessibilityAuthorizing: AnyObject {
    var isTrusted: Bool { get }

    @discardableResult
    func requestAccessIfNeeded() -> Bool
}
