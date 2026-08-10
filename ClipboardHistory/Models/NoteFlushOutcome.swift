import Foundation

enum NoteFlushOutcome: Equatable, Sendable {
    case saved
    case nothingToSave
    case failed

    var allowsTransition: Bool {
        self != .failed
    }
}
