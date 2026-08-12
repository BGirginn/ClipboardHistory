import Foundation

@objc protocol BrowserAudioBridgeControllerProtocol {
    func handleBrowserAudioPayload(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}
