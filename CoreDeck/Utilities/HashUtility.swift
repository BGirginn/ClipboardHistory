import CryptoKit
import Foundation

enum HashUtility {
    static func sha256(text: String) -> String {
        sha256(data: Data(text.utf8))
    }

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).reduce(into: "") { result, byte in
            let hexadecimal = String(byte, radix: 16)
            result += hexadecimal.count == 1 ? "0\(hexadecimal)" : hexadecimal
        }
    }

    static func sha256(orderedData: [Data]) -> String {
        var hasher = SHA256()
        for data in orderedData {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
            hasher.update(data: data)
        }
        return hasher.finalize().reduce(into: "") { result, byte in
            let hexadecimal = String(byte, radix: 16)
            result += hexadecimal.count == 1 ? "0\(hexadecimal)" : hexadecimal
        }
    }
}
