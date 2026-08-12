import Foundation

struct AppShutdownOutcome: Equatable, Sendable {
    let notes: NoteFlushOutcome
    let clipboard: ClipboardFlushOutcome
    let blockedFeature: AppFeature?

    var allowsTermination: Bool {
        blockedFeature == nil
    }
}
