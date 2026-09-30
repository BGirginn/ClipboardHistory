import Foundation

enum ClipboardFlushOutcome: Equatable, Sendable {
    case notAttempted
    case saved
    case failed
}
