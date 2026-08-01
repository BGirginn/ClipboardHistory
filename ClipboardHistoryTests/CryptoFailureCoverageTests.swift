import CommonCrypto
import CryptoKit
import Foundation
import Security
import XCTest

@testable import ClipboardHistory

final class CryptoFailureCoverageTests: XCTestCase {
    func testEncryptionBackendCoversLiveSuccessAndFailClosedSealPath() throws {
        let key = Data(repeating: 7, count: 32)
        let live = try EncryptionService.live(keyLoader: { key })
        let plaintext = Data("live encryption".utf8)
        XCTAssertEqual(try live.decrypt(live.encrypt(plaintext)), plaintext)

        let failClosed = EncryptionService.ephemeral(
            cryptoBackend: NilEncryptionCryptoBackend()
        )
        XCTAssertThrowsError(try failClosed.encrypt(plaintext))
        XCTAssertThrowsError(try failClosed.decrypt(Data([1, 2, 3])))
    }

    func testPasswordArchiveRejectsEveryInjectedCryptoFailure() throws {
        let plaintext = Data("archive".utf8)
        XCTAssertThrowsError(try PasswordArchiveCrypto.encrypt(plaintext, password: ""))
        XCTAssertThrowsError(try PasswordArchiveCrypto.decrypt(Data(), password: ""))
        XCTAssertThrowsError(try PasswordArchiveCrypto.decrypt(Data([1]), password: "password"))

        XCTAssertThrowsError(
            try PasswordArchiveCrypto.encrypt(
                plaintext,
                password: "password",
                backend: StubPasswordArchiveCryptoBackend(randomStatus: errSecNotAvailable)
            )
        )
        XCTAssertThrowsError(
            try PasswordArchiveCrypto.encrypt(
                plaintext,
                password: "password",
                backend: StubPasswordArchiveCryptoBackend(deriveStatus: Int32(kCCParamError))
            )
        )
        XCTAssertThrowsError(
            try PasswordArchiveCrypto.encrypt(
                plaintext,
                password: "password",
                backend: StubPasswordArchiveCryptoBackend(derivedKey: Data([1]))
            )
        )
        XCTAssertThrowsError(
            try PasswordArchiveCrypto.encrypt(
                plaintext,
                password: "password",
                backend: StubPasswordArchiveCryptoBackend(sealedData: nil)
            )
        )
    }

    func testPasswordArchiveRejectsInvalidRoundsAndInjectedOpenFailure() throws {
        let encrypted = try PasswordArchiveCrypto.encrypt(
            Data("archive".utf8),
            password: "password"
        )
        var invalidRounds = encrypted
        invalidRounds.replaceSubrange(22..<26, with: [0, 0, 0, 0])
        XCTAssertThrowsError(
            try PasswordArchiveCrypto.decrypt(invalidRounds, password: "password")
        )

        XCTAssertThrowsError(
            try PasswordArchiveCrypto.decrypt(
                encrypted,
                password: "password",
                backend: StubPasswordArchiveCryptoBackend(openError: StubCryptoError.expected)
            )
        )
    }
}

private enum StubCryptoError: Error {
    case expected
}

private struct NilEncryptionCryptoBackend: EncryptionCryptoBackend {
    func seal(_ data: Data, using key: SymmetricKey) throws -> Data? {
        nil
    }

    func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        throw StubCryptoError.expected
    }
}

private struct StubPasswordArchiveCryptoBackend: PasswordArchiveCryptoBackend {
    var randomStatus: OSStatus = errSecSuccess
    var deriveStatus: Int32 = Int32(kCCSuccess)
    var derivedKey = Data(repeating: 1, count: 32)
    var sealedData: Data? = Data([1])
    var openError: Error?

    func randomData(count: Int) -> (status: OSStatus, data: Data) {
        (randomStatus, Data(repeating: 2, count: count))
    }

    func deriveKeyData(
        password: String,
        salt: Data,
        rounds: UInt32,
        keyLength: Int
    ) -> (status: Int32, data: Data) {
        (deriveStatus, derivedKey)
    }

    func seal(_ data: Data, using key: SymmetricKey) throws -> Data? {
        sealedData
    }

    func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        if let openError { throw openError }
        return data
    }
}
