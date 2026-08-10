import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let requestName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Request")
    private let responseName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Response")
    private let maximumMessageSize = 256 * 1024

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey],
              JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              data.count <= maximumMessageSize,
              let payload = String(data: data, encoding: .utf8) else {
            context.cancelRequest(withError: BridgeError.invalidMessage)
            return
        }

        let requestID = UUID().uuidString
        let responsePayload = LockedResponsePayload()
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: responseName,
            object: requestID,
            queue: .main
        ) { notification in
            responsePayload.store(notification.userInfo?["payload"] as? String)
        }

        DistributedNotificationCenter.default().postNotificationName(
            requestName,
            object: requestID,
            userInfo: ["payload": payload],
            deliverImmediately: true
        )

        let deadline = Date.now.addingTimeInterval(0.4)
        while responsePayload.load() == nil,
              RunLoop.current.run(mode: .default, before: deadline),
              Date.now < deadline {}
        DistributedNotificationCenter.default().removeObserver(observer)

        let responseData = (responsePayload.load() ?? "{\"version\":1,\"commands\":[]}").data(using: .utf8)
        let response = responseData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? ["version": 1, "commands": []]
        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [responseItem])
    }
}

private final class LockedResponsePayload: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func store(_ newValue: String?) {
        lock.withLock { value = newValue }
    }

    func load() -> String? {
        lock.withLock { value }
    }
}

private enum BridgeError: LocalizedError {
    case invalidMessage

    var errorDescription: String? { "The Safari audio bridge rejected an invalid message." }
}
