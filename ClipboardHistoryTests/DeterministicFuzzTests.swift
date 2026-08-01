import Foundation
import XCTest

@testable import ClipboardHistory

final class DeterministicFuzzTests: XCTestCase {
    func testTenThousandDeterministicHostileInputsDoNotBypassValidation() {
        var generator = SplitMix64(seed: 0x434C_4950_424F_4152)
        for index in 0..<10_000 {
            let length = Int(generator.next() % 257)
            let bytes = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
            XCTAssertThrowsError(
                try PasswordArchiveCrypto.decrypt(bytes, password: "fuzz-password"),
                "Random input unexpectedly decrypted at case \(index)."
            )
            _ = HTMLSanitizer.sanitize(bytes)
            let string = String(decoding: bytes, as: UTF8.self)
            if string.contains("/") || string.contains("\\") || string.contains("\0") {
                XCTAssertNil(ManagedFilename(string))
            }
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
