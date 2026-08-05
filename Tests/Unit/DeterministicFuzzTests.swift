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

    func testExpandedMalformedMediaCorpusFailsSafely() async {
        let signatures: [Data] = [
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), // PNG
            Data([0xFF, 0xD8, 0xFF]), // JPEG
            Data("GIF89a".utf8),
            Data([0x49, 0x49, 0x2A, 0x00]), // TIFF
            Data("BM".utf8),
            Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]), // HEIC
            Data("%PDF-1.7\n".utf8),
            Data("{\\rtf1\\ansi ".utf8)
        ]
        let processor = ClipboardProcessingService()
        var generator = SplitMix64(seed: 0x4D45_4449_4143_4F52)

        for caseIndex in 0..<512 {
            let signature = signatures[caseIndex % signatures.count]
            let suffixLength = Int(generator.next() % 1_024)
            var bytes = signature
            bytes.append(contentsOf: (0..<suffixLength).map { _ in
                UInt8(truncatingIfNeeded: generator.next())
            })

            _ = ImageMetadataUtility.dimensions(for: bytes)
            _ = await processor.process(.images(data: [bytes]), sourceBundleIdentifier: nil)
            _ = await processor.process(.pdf(data: bytes), sourceBundleIdentifier: nil)
            _ = await processor.process(
                .text(
                    value: String(decoding: bytes, as: UTF8.self),
                    rtfData: bytes,
                    htmlData: bytes
                ),
                sourceBundleIdentifier: nil
            )
            _ = HTMLSanitizer.sanitize(bytes)
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
