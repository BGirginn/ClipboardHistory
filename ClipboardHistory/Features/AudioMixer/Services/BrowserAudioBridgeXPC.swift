import Foundation

enum BrowserAudioBridgeXPC {
    static let serviceName = "com.brgirgin.ClipboardHistory.BrowserAudioBridge"
    static let maximumMessageSize = 256 * 1_024

    static func serviceInterface() -> NSXPCInterface {
        NSXPCInterface(with: BrowserAudioBridgeServiceProtocol.self)
    }

    static func controllerInterface() -> NSXPCInterface {
        NSXPCInterface(with: BrowserAudioBridgeControllerProtocol.self)
    }
}
