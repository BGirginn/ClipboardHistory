import Foundation

struct SecretDetectionService: Sendable {
    private static let passwordManagerBundleFragments = [
        "1password", "agilebits", "bitwarden", "lastpass", "dashlane", "keepass"
    ]

    func detect(in text: String, sourceBundleIdentifier: String?) -> SecretDetectionResult {
        guard !text.isEmpty else {
            return SecretDetectionResult(isSensitive: false, confidence: 0, signals: [])
        }

        var score = 0.0
        var signals: [String] = []
        let candidates: [(String, String, Double)] = [
            (#"-----BEGIN (OPENSSH|RSA|EC|DSA|PGP|PRIVATE) PRIVATE KEY-----"#, "private-key", 1.0),
            (#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#, "jwt", 0.95),
            (#"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#, "github-token", 0.95),
            (#"\bsk-[A-Za-z0-9_-]{20,}\b"#, "api-key-prefix", 0.9),
            (#"\bAKIA[0-9A-Z]{16}\b"#, "aws-access-key", 0.95),
            (#"\bAIza[0-9A-Za-z_-]{30,}\b"#, "google-api-key", 0.9),
            (#"\bxox[baprs]-[A-Za-z0-9-]{16,}\b"#, "slack-token", 0.95),
            (#"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b"#, "payment-api-key", 0.95),
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}"#, "bearer-token", 0.95),
            (#"(?i)\bAuthorization\s*:\s*[^\s]{12,}"#, "authorization-header", 0.95),
            (#"(?i)\b(password|passwd|pwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s]{8,}"#, "secret-context", 0.9),
            (#"(?i)\b(postgres|mysql|mongodb(?:\+srv)?|redis)://[^\s]+:[^\s]+@"#, "connection-string", 0.95),
            (#"(?i)\b(DATABASE_URL|REDIS_URL|CONNECTION_STRING)\s*=\s*[^\s]{12,}"#, "environment-connection", 0.9),
            (#"(?i)\brecovery\s+codes?\b[\s\S]{0,80}\b[A-Z0-9]{4,8}[- ]?[A-Z0-9]{4,8}\b"#, "recovery-code", 0.9)
        ]

        for (pattern, signal, weight) in candidates where text.range(
            of: pattern,
            options: .regularExpression
        ) != nil {
            score = max(score, weight)
            signals.append(signal)
        }

        if containsLikelyCreditCard(text) {
            score = max(score, 0.85)
            signals.append("payment-card")
        }

        let source = sourceBundleIdentifier?.lowercased() ?? ""
        if Self.passwordManagerBundleFragments.contains(where: source.contains) {
            score = max(score, text.count >= 8 ? 0.8 : 0.55)
            signals.append("password-manager-source")
        }

        let compact = text.filter { !$0.isWhitespace }
        if compact.count >= 20, compact.count <= 512, shannonEntropy(of: compact) >= 4.2 {
            score += text.contains(" ") ? 0.05 : 0.2
            signals.append("high-entropy")
        }

        let confidence = min(score, 1)
        return SecretDetectionResult(
            isSensitive: confidence >= 0.75,
            confidence: confidence,
            signals: signals
        )
    }

    private func shannonEntropy(of value: String) -> Double {
        let characters = Array(value.utf8)
        guard !characters.isEmpty else { return 0 }
        let counts = Dictionary(grouping: characters, by: { $0 }).mapValues(\.count)
        let length = Double(characters.count)
        return counts.values.reduce(0) { entropy, count in
            let probability = Double(count) / length
            return entropy - probability * log2(probability)
        }
    }

    private func containsLikelyCreditCard(_ text: String) -> Bool {
        let groups = text.matches(of: /(?:\d[ -]?){13,19}/)
        return groups.contains { match in
            let digits = match.output.filter(\.isNumber).compactMap(\.wholeNumberValue)
            return (13...19).contains(digits.count) && passesLuhn(digits)
        }
    }

    private func passesLuhn(_ digits: [Int]) -> Bool {
        let sum = digits.reversed().enumerated().reduce(0) { result, pair in
            let (offset, digit) = pair
            if offset.isMultiple(of: 2) { return result + digit }
            let doubled = digit * 2
            return result + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}
