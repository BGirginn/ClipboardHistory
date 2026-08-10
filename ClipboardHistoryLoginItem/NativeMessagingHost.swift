import Foundation
import os

enum NativeMessagingHost {
    private static let allowedOrigin = "chrome-extension://cgflaocbdgjkjlnoiolchhogcaepfmpf/"
    private static let requestName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Request")
    private static let responseName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Response")
    private static let maximumMessageSize = 256 * 1024

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.dropFirst().contains(allowedOrigin)
    }

    static func run() {
        while let payload = readMessage() {
            let requestID = UUID().uuidString
            let responsePayload = OSAllocatedUnfairLock<String?>(initialState: nil)
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: responseName,
                object: requestID,
                queue: nil
            ) { notification in
                let payload = notification.userInfo?["payload"] as? String
                responsePayload.withLock { $0 = payload }
            }
            DistributedNotificationCenter.default().postNotificationName(
                requestName,
                object: requestID,
                userInfo: ["payload": payload],
                deliverImmediately: true
            )
            let deadline = Date.now.addingTimeInterval(0.4)
            while responsePayload.withLock({ $0 }) == nil,
                  RunLoop.current.run(mode: .default, before: deadline),
                  Date.now < deadline {}
            DistributedNotificationCenter.default().removeObserver(observer)
            writeMessage(responsePayload.withLock { $0 } ?? "{\"version\":1,\"commands\":[]}")
        }
    }

    private static func readMessage() -> String? {
        let lengthData = FileHandle.standardInput.readData(ofLength: 4)
        guard lengthData.count == 4 else { return nil }
        let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        guard length > 0, length <= maximumMessageSize else { return nil }
        let data = FileHandle.standardInput.readData(ofLength: Int(length))
        guard data.count == Int(length) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeMessage(_ message: String) {
        guard let data = message.data(using: .utf8), data.count <= maximumMessageSize else { return }
        var length = UInt32(data.count).littleEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        FileHandle.standardOutput.write(header)
        FileHandle.standardOutput.write(data)
        try? FileHandle.standardOutput.synchronize()
    }
}
