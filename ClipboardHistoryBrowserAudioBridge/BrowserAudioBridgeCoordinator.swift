import Foundation

final class BrowserAudioBridgeCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private weak var controllerConnection: NSXPCConnection?

    func registerController(_ connection: NSXPCConnection, bundleIdentifier: String) -> Bool {
        guard bundleIdentifier == "com.brgirgin.ClipboardHistory" else { return false }
        lock.withLock { controllerConnection = connection }
        return true
    }

    func removeController(_ connection: NSXPCConnection) {
        lock.withLock {
            if controllerConnection === connection {
                controllerConnection = nil
            }
        }
    }

    func exchange(_ payload: Data, reply: @escaping (Data?) -> Void) {
        guard payload.count <= BrowserAudioBridgeXPC.maximumMessageSize else {
            reply(nil)
            return
        }
        guard let connection = lock.withLock({ controllerConnection }) else {
            reply(nil)
            return
        }
        let once = SingleReply(reply)
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            once.send(nil)
        } as? BrowserAudioBridgeControllerProtocol
        guard let proxy else {
            once.send(nil)
            return
        }
        proxy.handleBrowserAudioPayload(payload) { response in
            guard let response,
                  response.count <= BrowserAudioBridgeXPC.maximumMessageSize else {
                once.send(nil)
                return
            }
            once.send(response)
        }
    }
}

private final class SingleReply: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: ((Data?) -> Void)?

    init(_ reply: @escaping (Data?) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data?) {
        let callback = lock.withLock { () -> ((Data?) -> Void)? in
            defer { reply = nil }
            return reply
        }
        callback?(data)
    }
}
