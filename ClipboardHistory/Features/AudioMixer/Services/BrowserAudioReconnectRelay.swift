import Foundation

final class BrowserAudioReconnectRelay: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable () -> Void

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func requestReconnect() {
        Task { @MainActor [handler] in handler() }
    }
}
