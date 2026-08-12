import Foundation

@main
enum BrowserAudioBridgeServiceMain {
    static func main() {
        let listener = NSXPCListener.service()
        let delegate = BrowserAudioBridgeListenerDelegate()
        listener.delegate = delegate
        withExtendedLifetime(delegate) {
            listener.resume()
            dispatchMain()
        }
    }
}

private final class BrowserAudioBridgeListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let validator = BrowserAudioBridgeClientValidator()
    private let coordinator = BrowserAudioBridgeCoordinator()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let bundleIdentifier = validator.validatedBundleIdentifier(for: connection) else {
            return false
        }
        let handler = BrowserAudioBridgeConnectionHandler(
            bundleIdentifier: bundleIdentifier,
            connection: connection,
            coordinator: coordinator
        )
        connection.exportedInterface = NSXPCInterface(with: BrowserAudioBridgeServiceProtocol.self)
        connection.exportedObject = handler
        if bundleIdentifier == "com.brgirgin.ClipboardHistory" {
            connection.remoteObjectInterface = NSXPCInterface(with: BrowserAudioBridgeControllerProtocol.self)
        }
        connection.invalidationHandler = { [weak connection, coordinator] in
            guard let connection else { return }
            coordinator.removeController(connection)
        }
        connection.resume()
        return true
    }
}
