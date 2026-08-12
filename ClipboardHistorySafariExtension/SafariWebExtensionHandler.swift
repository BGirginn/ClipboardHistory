import Foundation
import SafariServices

private enum BrowserAudioBridgeXPC {
    static let serviceName = "com.brgirgin.ClipboardHistory.BrowserAudioBridge"
    static let maximumMessageSize = 256 * 1_024
}

@objc private protocol BrowserAudioBridgeServiceProtocol {
    func registerController(withReply reply: @escaping (Bool) -> Void)
    func exchange(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey],
              JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              data.count <= BrowserAudioBridgeXPC.maximumMessageSize else {
            context.cancelRequest(withError: BridgeError.invalidMessage)
            return
        }

        let connection = NSXPCConnection(machServiceName: BrowserAudioBridgeXPC.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BrowserAudioBridgeServiceProtocol.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            Self.finish(context: context, responseData: nil, connection: connection)
        } as? BrowserAudioBridgeServiceProtocol
        guard let proxy else {
            Self.finish(context: context, responseData: nil, connection: connection)
            return
        }
        proxy.exchange(data) { responseData in
            Self.finish(context: context, responseData: responseData, connection: connection)
        }
    }

    private static func finish(
        context: NSExtensionContext,
        responseData: Data?,
        connection: NSXPCConnection
    ) {
        connection.invalidate()
        let response = responseData.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            ?? ["version": 1, "commands": []]
        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [responseItem])
    }
}

private enum BridgeError: LocalizedError {
    case invalidMessage

    var errorDescription: String? { "The Safari audio bridge rejected an invalid message." }
}
