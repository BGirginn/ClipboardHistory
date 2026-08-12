import Foundation

@objc protocol BrowserAudioBridgeServiceProtocol {
    func registerController(withReply reply: @escaping (Bool) -> Void)
    func exchange(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}
