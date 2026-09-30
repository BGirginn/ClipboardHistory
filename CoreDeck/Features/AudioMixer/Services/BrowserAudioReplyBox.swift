import Foundation

final class BrowserAudioReplyBox: @unchecked Sendable {
    private let reply: (Data?) -> Void

    init(_ reply: @escaping (Data?) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data?) {
        reply(data)
    }
}
