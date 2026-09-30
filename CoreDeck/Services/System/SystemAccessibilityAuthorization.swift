import ApplicationServices
import Foundation

@MainActor
final class SystemAccessibilityAuthorization: AccessibilityAuthorizing {
    private let promptedTrustEvaluator: (CFDictionary) -> Bool
    private let trustEvaluator: () -> Bool
    private var requestedAccessThisSession = false

    init(
        promptedTrustEvaluator: @escaping (CFDictionary) -> Bool = AXIsProcessTrustedWithOptions,
        trustEvaluator: @escaping () -> Bool = AXIsProcessTrusted
    ) {
        self.promptedTrustEvaluator = promptedTrustEvaluator
        self.trustEvaluator = trustEvaluator
    }

    var isTrusted: Bool {
        trustEvaluator()
    }

    func requestAccessIfNeeded() -> Bool {
        guard !isTrusted else { return true }
        guard !requestedAccessThisSession else { return false }
        requestedAccessThisSession = true
        let options = ["AXTrustedCheckOptionPrompt": true]
        return promptedTrustEvaluator(options as CFDictionary)
    }
}
