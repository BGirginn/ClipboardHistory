import Foundation

final class MainActorSignalRelay: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable () -> Void

    private let handler: Handler
    private let lock = NSLock()
    private var isSignalPending = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func signal() {
        lock.lock()
        guard !isSignalPending else {
            lock.unlock()
            return
        }
        isSignalPending = true
        lock.unlock()
        Task { @MainActor [weak self, handler] in
            self?.clearPendingSignal()
            handler()
        }
    }

    nonisolated func callback() -> @Sendable () -> Void {
        { [self] in signal() }
    }

    private nonisolated func clearPendingSignal() {
        lock.lock()
        isSignalPending = false
        lock.unlock()
    }
}
