import Foundation
@testable import ClipboardHistory

@MainActor
final class StubSystemAuthenticator: SystemAuthenticating {
    private(set) var reasons: [String] = []
    var handler: (String) async throws -> Bool

    init(handler: @escaping (String) async throws -> Bool) {
        self.handler = handler
    }

    func authenticate(reason: String) async throws -> Bool {
        reasons.append(reason)
        return try await handler(reason)
    }
}
