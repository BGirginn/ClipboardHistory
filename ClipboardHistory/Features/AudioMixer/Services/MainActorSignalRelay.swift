import Foundation

final class MainActorSignalRelay: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable () -> Void

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func signal() {
        Task { @MainActor [handler] in handler() }
    }

    nonisolated func callback() -> @Sendable () -> Void {
        { [self] in signal() }
    }
}
