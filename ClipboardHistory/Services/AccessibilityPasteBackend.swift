import Foundation

@MainActor
protocol AccessibilityPasteBackend: AnyObject {
    var frontmostProcessIdentifier: pid_t? { get }
    func isTrusted(prompt: Bool) -> Bool
    func isProcessAvailable(_ processIdentifier: pid_t) -> Bool
    func activate(_ processIdentifier: pid_t)
    func waitBeforePosting() async
    func postCommandV(to processIdentifier: pid_t) -> Bool
}
