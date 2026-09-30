import Foundation

struct SecretDetectionResult: Equatable, Sendable {
    let isSensitive: Bool
    let confidence: Double
    let signals: [String]
}
