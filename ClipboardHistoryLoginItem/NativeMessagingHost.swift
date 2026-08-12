import Foundation

private enum BrowserAudioBridgeXPC {
    static let serviceName = "com.brgirgin.ClipboardHistory.BrowserAudioBridge"
    static let maximumMessageSize = 256 * 1_024
}

@objc private protocol BrowserAudioBridgeServiceProtocol {
    func registerController(withReply reply: @escaping (Bool) -> Void)
    func exchange(_ payload: Data, withReply reply: @escaping (Data?) -> Void)
}

enum NativeMessagingHost {
    private static let allowedOrigin = "chrome-extension://cgflaocbdgjkjlnoiolchhogcaepfmpf/"
    private static let emptyResponse = Data("{\"version\":1,\"commands\":[]}".utf8)

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.dropFirst().contains(allowedOrigin)
    }

    static func run() {
        let connection = NSXPCConnection(machServiceName: BrowserAudioBridgeXPC.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BrowserAudioBridgeServiceProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        while let payload = readMessage() {
            writeMessage(exchange(payload, using: connection))
        }
    }

    private static func exchange(_ payload: Data, using connection: NSXPCConnection) -> Data {
        let condition = NSCondition()
        var response: Data?
        var completed = false
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            condition.lock()
            completed = true
            condition.signal()
            condition.unlock()
        } as? BrowserAudioBridgeServiceProtocol

        condition.lock()
        proxy?.exchange(payload) { data in
            condition.lock()
            response = data
            completed = true
            condition.signal()
            condition.unlock()
        }
        let deadline = Date.now.addingTimeInterval(1)
        while !completed, condition.wait(until: deadline) {}
        condition.unlock()
        return response ?? emptyResponse
    }

    private static func readMessage() -> Data? {
        let lengthData = FileHandle.standardInput.readData(ofLength: 4)
        guard lengthData.count == 4 else { return nil }
        let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        guard length > 0, length <= BrowserAudioBridgeXPC.maximumMessageSize else { return nil }
        let data = FileHandle.standardInput.readData(ofLength: Int(length))
        guard data.count == Int(length) else { return nil }
        return data
    }

    private static func writeMessage(_ data: Data) {
        guard data.count <= BrowserAudioBridgeXPC.maximumMessageSize else { return }
        var length = UInt32(data.count).littleEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(data)
        try? FileHandle.standardOutput.synchronize()
    }
}
