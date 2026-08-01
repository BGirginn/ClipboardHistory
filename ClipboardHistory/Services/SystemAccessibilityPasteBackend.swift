import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SystemAccessibilityPasteBackend: AccessibilityPasteBackend {
    private let promptedTrustEvaluator: (CFDictionary) -> Bool
    private let trustEvaluator: () -> Bool

    init(
        promptedTrustEvaluator: @escaping (CFDictionary) -> Bool = AXIsProcessTrustedWithOptions,
        trustEvaluator: @escaping () -> Bool = AXIsProcessTrusted
    ) {
        self.promptedTrustEvaluator = promptedTrustEvaluator
        self.trustEvaluator = trustEvaluator
    }

    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true]
            return promptedTrustEvaluator(options as CFDictionary)
        }
        return trustEvaluator()
    }

    func isProcessAvailable(_ processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: processIdentifier
        ) else { return false }
        return !application.isTerminated
    }

    func activate(_ processIdentifier: pid_t) {
        NSRunningApplication(processIdentifier: processIdentifier)?.activate()
    }

    func waitBeforePosting() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
              ) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }
}
