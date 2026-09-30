import Foundation

final class BrowserAudioControllerEndpoint: NSObject, BrowserAudioBridgeControllerProtocol, @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (Data) -> Data?

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func handleBrowserAudioPayload(_ payload: Data, withReply reply: @escaping (Data?) -> Void) {
        let replyBox = BrowserAudioReplyBox(reply)
        Task { @MainActor [handler] in
            replyBox.send(handler(payload))
        }
    }
}
