import Foundation

@MainActor
final class AccessibilityPasteService: ActiveApplicationPasting, @unchecked Sendable {
    private var targetProcessIdentifier: pid_t?
    private let backend: any AccessibilityPasteBackend

    init(backend: any AccessibilityPasteBackend = SystemAccessibilityPasteBackend()) {
        self.backend = backend
    }

    func captureTargetApplication() {
        guard let processIdentifier = backend.frontmostProcessIdentifier,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        targetProcessIdentifier = processIdentifier
    }

    func paste() async -> ActiveApplicationPasteResult {
        guard backend.isTrusted(prompt: false) else {
            _ = backend.isTrusted(prompt: true)
            return .permissionRequired
        }
        guard let targetProcessIdentifier,
              backend.isProcessAvailable(targetProcessIdentifier) else {
            return .targetUnavailable
        }
        backend.activate(targetProcessIdentifier)
        await backend.waitBeforePosting()
        guard backend.postCommandV(to: targetProcessIdentifier) else {
            return .eventCreationFailed
        }
        return .pasted
    }
}
