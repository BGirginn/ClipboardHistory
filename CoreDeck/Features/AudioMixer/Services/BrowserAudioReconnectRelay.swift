import Foundation

final class BrowserAudioReconnectRelay: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable () -> Void
    typealias RegistrationHandler = @MainActor @Sendable (Bool) -> Void

    private let handler: Handler
    private let registrationHandler: RegistrationHandler

    init(
        handler: @escaping Handler,
        registrationHandler: @escaping RegistrationHandler = { _ in }
    ) {
        self.handler = handler
        self.registrationHandler = registrationHandler
    }

    func requestReconnect() {
        Task { @MainActor [handler] in handler() }
    }

    func reportRegistration(_ accepted: Bool) {
        Task { @MainActor [registrationHandler] in registrationHandler(accepted) }
    }
}
