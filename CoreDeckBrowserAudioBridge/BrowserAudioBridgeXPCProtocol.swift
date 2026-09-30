import Foundation

enum BrowserAudioBridgeXPC {
    static let maximumMessageSize = 256 * 1_024
}

@objc protocol BrowserAudioBridgeServiceProtocol {
    func registerController(withReply reply: @escaping (Bool) -> Void)
    func exchange(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}

@objc protocol BrowserAudioBridgeControllerProtocol {
    func handleBrowserAudioPayload(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}
