import Foundation

final class BrowserAudioBridgeConnectionHandler: NSObject, BrowserAudioBridgeServiceProtocol {
    private let bundleIdentifier: String
    private let connection: NSXPCConnection
    private let coordinator: BrowserAudioBridgeCoordinator

    init(
        bundleIdentifier: String,
        connection: NSXPCConnection,
        coordinator: BrowserAudioBridgeCoordinator
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.connection = connection
        self.coordinator = coordinator
    }

    func registerController(withReply reply: @escaping (Bool) -> Void) {
        reply(coordinator.registerController(connection, bundleIdentifier: bundleIdentifier))
    }

    func exchange(_ payload: Data, withReply reply: @escaping (Data?) -> Void) {
        guard bundleIdentifier == "com.brgirgin.ClipboardHistory.LoginItem"
                || bundleIdentifier == "com.brgirgin.ClipboardHistory.SafariExtension" else {
            reply(nil)
            return
        }
        coordinator.exchange(payload, reply: reply)
    }
}
