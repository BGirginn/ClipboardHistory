import AppKit
import Foundation
import PDFKit
import ServiceManagement
import XCTest

@testable import ClipboardHistory

@MainActor
final class CoverageCompletionTests: XCTestCase {
    func testLocalizedErrorsExposeEveryUserFacingDescription() {
        let databaseErrors: [DatabaseError] = [
            .openFailed("open"),
            .executionFailed("execute"),
            .preparationFailed("prepare"),
            .bindingFailed,
            .corrupt,
            .encryptionUnavailable,
            .unsafeFilename,
            .closed
        ]
        let encryptionErrors: [EncryptionServiceError] = [
            .keychain(errSecAuthFailed),
            .invalidKey,
            .invalidCiphertext,
            .encryptionUnavailable
        ]
        let archiveErrors: [ExportImportError] = [
            .passwordRequired,
            .invalidArchive,
            .unsupportedVersion,
            .unsafePath,
            .archiveTooLarge,
            .missingAsset
        ]

        XCTAssertTrue(databaseErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        XCTAssertTrue(encryptionErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        XCTAssertTrue(archiveErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    func testTextTransformationMetadataAndEveryClassifierBranch() {
        let expectedTitles = ["Uppercase", "Lowercase", "Title Case", "Trim Surrounding Whitespace"]
        XCTAssertEqual(TextTransformation.allCases.map(\.title), expectedTitles)
        XCTAssertEqual(TextTransformation.allCases.map(\.id), TextTransformation.allCases)
        XCTAssertEqual(TextTransformation.uppercase.apply(to: "abc", locale: .init(identifier: "en_US")), "ABC")
        XCTAssertEqual(TextTransformation.lowercase.apply(to: "ABC", locale: .init(identifier: "en_US")), "abc")
        XCTAssertEqual(TextTransformation.titleCase.apply(to: "hello world", locale: .init(identifier: "en_US")), "Hello World")
        XCTAssertEqual(TextTransformation.trimWhitespace.apply(to: " \nvalue\t"), "value")

        XCTAssertEqual(TextClassifier.subtype(for: "#aabbcc"), .color)
        XCTAssertEqual(TextClassifier.subtype(for: "https://example.com"), .url)
        XCTAssertEqual(TextClassifier.subtype(for: "person@example.com"), .email)
        XCTAssertEqual(TextClassifier.subtype(for: "/tmp/file"), .filePath)
        XCTAssertEqual(TextClassifier.subtype(for: "~/file"), .filePath)
        XCTAssertEqual(TextClassifier.subtype(for: "func value() {}"), .sourceCode)
        XCTAssertEqual(TextClassifier.subtype(for: "value { body }"), .sourceCode)
        XCTAssertEqual(TextClassifier.subtype(for: "ordinary words"), .plainText)

        XCTAssertEqual(PasteRepresentation.allCases.map(\.id), PasteRepresentation.allCases)
        XCTAssertEqual(
            PasteRepresentation.allCases.map(\.title),
            ["Original", "Plain Text", "RTF", "Clean HTML"]
        )
    }

    func testClipboardProcessingCoversEveryRawRepresentationAndInvalidInput() async throws {
        let service = ClipboardProcessingService()
        let html = Data("<b>safe</b><script>bad()</script>".utf8)
        let htmlResult = await service.process(
            .text(value: "Safe", rtfData: nil, htmlData: html),
            sourceBundleIdentifier: "com.example.html"
        )
        guard case let .text(_, _, sanitizedHTML, subtype, _, source) = htmlResult else {
            return XCTFail("Expected processed HTML")
        }
        XCTAssertEqual(subtype, .html)
        XCTAssertEqual(source, "com.example.html")
        XCTAssertFalse(String(decoding: try XCTUnwrap(sanitizedHTML), as: UTF8.self).contains("script"))

        let rtf = Data("{\\rtf1 value}".utf8)
        let rtfResult = await service.process(
            .text(value: "RTF", rtfData: rtf, htmlData: Data([0xFF])),
            sourceBundleIdentifier: nil
        )
        guard case let .text(_, returnedRTF, nil, rtfSubtype, rtfHash, _) = rtfResult else {
            return XCTFail("Expected processed RTF")
        }
        XCTAssertEqual(returnedRTF, rtf)
        XCTAssertEqual(rtfSubtype, .rtf)
        XCTAssertEqual(rtfHash, HashUtility.sha256(data: rtf))

        let urlResult = await service.process(
            .text(value: "HTTPS://Example.COM/path/", rtfData: nil, htmlData: nil),
            sourceBundleIdentifier: nil
        )
        XCTAssertNotNil(urlResult)

        let png = try makePNG(width: 3, height: 2)
        let pngResult = await service.process(
            .images(data: [png, png]),
            sourceBundleIdentifier: "com.example.images"
        )
        guard case let .images(pngData, imageHash, imageSource) = pngResult else {
            return XCTFail("Expected processed images")
        }
        XCTAssertEqual(pngData, [png, png])
        XCTAssertEqual(imageHash, HashUtility.sha256(orderedData: [png, png]))
        XCTAssertEqual(imageSource, "com.example.images")

        let image = try XCTUnwrap(NSImage(data: png))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let convertedResult = await service.process(
            .images(data: [tiff]),
            sourceBundleIdentifier: nil
        )
        guard case let .images(converted, _, _) = convertedResult else {
            return XCTFail("Expected converted TIFF")
        }
        XCTAssertTrue(try XCTUnwrap(converted.first).starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let invalidImages = await service.process(
            .images(data: [Data("invalid".utf8)]),
            sourceBundleIdentifier: nil
        )
        XCTAssertNil(invalidImages)

        let pdf = Data("%PDF-1.7\ncontent".utf8)
        let validPDF = await service.process(.pdf(data: pdf), sourceBundleIdentifier: nil)
        let invalidPDF = await service.process(
            .pdf(data: Data("invalid".utf8)),
            sourceBundleIdentifier: nil
        )
        XCTAssertNotNil(validPDF)
        XCTAssertNil(invalidPDF)

        let emptyFiles = await service.process(
            .files(urls: [], bookmarks: []),
            sourceBundleIdentifier: nil
        )
        XCTAssertNil(emptyFiles)
        let file = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardProcessing-\(UUID().uuidString).txt"
        )
        try Data("file".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let filesResult = await service.process(
            .files(
                urls: [file, file.appending(path: "missing")],
                bookmarks: [Data("bookmark".utf8)]
            ),
            sourceBundleIdentifier: "com.example.files"
        )
        guard case let .files(urls, bookmarks, _, filesSource) = filesResult else {
            return XCTFail("Expected processed files")
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(filesSource, "com.example.files")
    }

    func testClipboardItemValidationAndEveryLegacySubtype() throws {
        XCTAssertFalse(ClipboardItem(type: .text, text: "value", hash: "").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .text, hash: "text").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .text, text: "value", imageFilename: "image", hash: "text-image").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .image, hash: "image").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .richText, hash: "rich").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .pdf, hash: "pdf").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .files, hash: "files").isStructurallyValid)
        XCTAssertFalse(ClipboardItem(type: .imageGroup, hash: "images").isStructurallyValid)

        let expected: [(ClipboardItemType, ClipboardContentSubtype)] = [
            (.text, .plainText),
            (.image, .image),
            (.richText, .rtf),
            (.pdf, .pdf),
            (.files, .file),
            (.imageGroup, .imageGroup)
        ]
        for (type, subtype) in expected {
            let item = ClipboardItem(type: type, hash: type.rawValue)
            let encoded = try JSONEncoder().encode(item)
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            object["contentSubtype"] = nil
            let legacy = try JSONSerialization.data(withJSONObject: object)
            XCTAssertEqual(try JSONDecoder().decode(ClipboardItem.self, from: legacy).contentSubtype, subtype)
        }
    }

    func testContentMetadataReturnsDimensionsPageCountAndNilForInvalidData() async throws {
        let metadata = ContentMetadataService()
        let emptyDimensions = await metadata.dimensions(forFirstImage: [])
        let invalidDimensions = await metadata.dimensions(forFirstImage: [Data([0, 1, 2])])
        XCTAssertNil(emptyDimensions)
        XCTAssertNil(invalidDimensions)
        let png = try makePNG(width: 7, height: 5)
        let dimensions = await metadata.dimensions(forFirstImage: [png])
        XCTAssertEqual(dimensions, ImageDimensions(width: 14, height: 10))
        let invalidPageCount = await metadata.pageCount(forPDF: Data([0, 1, 2]))
        XCTAssertNil(invalidPageCount)

        let document = PDFDocument()
        let image = try XCTUnwrap(NSImage(data: png))
        let page = try XCTUnwrap(PDFPage(image: image))
        document.insert(page, at: 0)
        let pdf = try XCTUnwrap(document.dataRepresentation())
        let pageCount = await metadata.pageCount(forPDF: pdf)
        XCTAssertEqual(pageCount, 1)
    }

    func testLaunchAtLoginServiceCoversSuccessAndErrorRefresh() {
        let backend = CoverageLaunchAtLoginBackend()
        let service = LaunchAtLoginService(backend: backend)
        XCTAssertFalse(service.isEnabled)

        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertNil(service.errorMessage)

        backend.error = CocoaError(.featureUnsupported)
        service.setEnabled(false)
        XCTAssertTrue(service.isEnabled)
        XCTAssertNotNil(service.errorMessage)

        backend.error = nil
        backend.isEnabled = false
        service.refresh()
        XCTAssertFalse(service.isEnabled)
    }

    func testServiceManagementLaunchAtLoginBackendDelegatesBothTransitions() throws {
        let service = CoverageServiceManagementAppService()
        let backend = ServiceManagementLaunchAtLoginBackend(service: service)
        XCTAssertFalse(backend.isEnabled)
        try backend.setEnabled(true)
        XCTAssertTrue(backend.isEnabled)
        try backend.setEnabled(false)
        XCTAssertFalse(backend.isEnabled)
        XCTAssertEqual(service.transitions, [true, false])
    }

    func testSystemRepeatingTimerRunsAndCancellationIsIdempotent() async {
        let fired = expectation(description: "timer fired")
        fired.expectedFulfillmentCount = 2
        fired.assertForOverFulfill = false
        let token = SystemRepeatingTimerScheduler().schedule(
            interval: 0.01,
            tolerance: 0
        ) {
            fired.fulfill()
        }
        await fulfillment(of: [fired], timeout: 1)
        token.cancel()
        token.cancel()
    }

    func testLoggerCategoriesInitialize() {
        _ = AppLog.clipboard
        _ = AppLog.storage
        _ = AppLog.lifecycle
        _ = AppLog.performance
    }

    func testKeychainServiceCoversLoadCreateDuplicateAndRotation() throws {
        let existing = Data(repeating: 1, count: 32)
        let existingClient = CoverageKeychainClient(copyResults: [(errSecSuccess, existing)])
        XCTAssertEqual(
            try KeychainService(client: existingClient).loadOrCreateKey(),
            existing
        )

        let generated = Data(repeating: 2, count: 32)
        let createClient = CoverageKeychainClient(
            copyResults: [(errSecItemNotFound, nil)],
            randomResult: (errSecSuccess, generated)
        )
        XCTAssertEqual(try KeychainService(client: createClient).loadOrCreateKey(), generated)
        XCTAssertEqual(createClient.addedData, generated)

        let duplicate = Data(repeating: 3, count: 32)
        let duplicateClient = CoverageKeychainClient(
            copyResults: [(errSecItemNotFound, nil), (errSecSuccess, duplicate)],
            addStatus: errSecDuplicateItem,
            randomResult: (errSecSuccess, generated)
        )
        XCTAssertEqual(try KeychainService(client: duplicateClient).loadOrCreateKey(), duplicate)

        let rotateClient = CoverageKeychainClient(copyResults: [])
        let provider = KeychainMasterKeyProvider(service: KeychainService(client: rotateClient))
        try provider.replaceKey(with: generated)
        XCTAssertEqual(rotateClient.updatedData, generated)

        let providerClient = CoverageKeychainClient(copyResults: [(errSecSuccess, existing)])
        let loadingProvider = KeychainMasterKeyProvider(
            service: KeychainService(client: providerClient)
        )
        XCTAssertEqual(try loadingProvider.loadOrCreateKey(), existing)
    }

    func testSystemKeychainClientRoundTripUsesOnlyAnEphemeralTestItem() throws {
        let client = SystemKeychainSecurityClient()
        let service = "com.brgirgin.ClipboardHistory.tests.\(UUID().uuidString)"
        let account = "temporary-test-key"
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let mutationQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        defer { _ = SecItemDelete(mutationQuery as CFDictionary) }

        XCTAssertEqual(client.copyMatching(lookup).status, errSecItemNotFound)
        let random = client.randomData(count: 32)
        XCTAssertEqual(random.status, errSecSuccess)
        XCTAssertEqual(random.data.count, 32)
        var addQuery = mutationQuery
        addQuery[kSecValueData as String] = random.data
        XCTAssertEqual(client.add(addQuery), errSecSuccess)
        XCTAssertEqual(client.copyMatching(lookup).data, random.data)

        let replacement = Data(repeating: 9, count: 32)
        XCTAssertEqual(
            client.update(
                mutationQuery,
                attributes: [kSecValueData as String: replacement]
            ),
            errSecSuccess
        )
        XCTAssertEqual(client.copyMatching(lookup).data, replacement)

        XCTAssertEqual(try KeychainService.generateRandomKey().count, 32)
    }

    func testKeychainServiceFailsClosedForEverySecurityError() {
        assertKeychainError(errSecAuthFailed) {
            _ = try KeychainService(
                client: CoverageKeychainClient(copyResults: [(errSecAuthFailed, nil)])
            ).loadOrCreateKey()
        }
        assertInvalidKey {
            _ = try KeychainService(
                client: CoverageKeychainClient(copyResults: [(errSecSuccess, Data([1]))])
            ).loadOrCreateKey()
        }
        assertKeychainError(errSecNotAvailable) {
            _ = try KeychainService(
                client: CoverageKeychainClient(
                    copyResults: [(errSecItemNotFound, nil)],
                    randomResult: (errSecNotAvailable, Data())
                )
            ).loadOrCreateKey()
        }
        assertInvalidKey {
            _ = try KeychainService(
                client: CoverageKeychainClient(
                    copyResults: [(errSecItemNotFound, nil)],
                    randomResult: (errSecSuccess, Data([1]))
                )
            ).loadOrCreateKey()
        }
        assertKeychainError(errSecDuplicateItem) {
            _ = try KeychainService(
                client: CoverageKeychainClient(
                    copyResults: [(errSecItemNotFound, nil), (errSecItemNotFound, nil)],
                    addStatus: errSecDuplicateItem,
                    randomResult: (errSecSuccess, Data(repeating: 4, count: 32))
                )
            ).loadOrCreateKey()
        }
        assertKeychainError(errSecNotAvailable) {
            _ = try KeychainService(
                client: CoverageKeychainClient(
                    copyResults: [(errSecItemNotFound, nil)],
                    addStatus: errSecNotAvailable,
                    randomResult: (errSecSuccess, Data(repeating: 5, count: 32))
                )
            ).loadOrCreateKey()
        }

        let rotateClient = CoverageKeychainClient(copyResults: [], updateStatus: errSecAuthFailed)
        assertInvalidKey {
            try KeychainService(client: rotateClient).rotateKey(with: Data([1]))
        }
        assertKeychainError(errSecAuthFailed) {
            try KeychainService(client: rotateClient).rotateKey(with: Data(repeating: 6, count: 32))
        }
    }

    private func assertInvalidKey(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case EncryptionServiceError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertKeychainError(
        _ expectedStatus: OSStatus,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case let EncryptionServiceError.keychain(status) = error else {
                return XCTFail("Expected keychain error, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(status, expectedStatus, file: file, line: line)
        }
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class CoverageLaunchAtLoginBackend: LaunchAtLoginBackend {
    var isEnabled = false
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
        isEnabled = enabled
    }
}

private final class CoverageKeychainClient: KeychainSecurityClient {
    private var copyResults: [(OSStatus, Data?)]
    private let addStatus: OSStatus
    private let updateStatus: OSStatus
    private let randomResult: (OSStatus, Data)
    private(set) var addedData: Data?
    private(set) var updatedData: Data?

    init(
        copyResults: [(OSStatus, Data?)],
        addStatus: OSStatus = errSecSuccess,
        updateStatus: OSStatus = errSecSuccess,
        randomResult: (OSStatus, Data) = (errSecSuccess, Data(repeating: 7, count: 32))
    ) {
        self.copyResults = copyResults
        self.addStatus = addStatus
        self.updateStatus = updateStatus
        self.randomResult = randomResult
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        XCTAssertEqual(query[kSecAttrService as String] as? String, KeychainService.service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, KeychainService.account)
        return copyResults.removeFirst()
    }

    func add(_ query: [String: Any]) -> OSStatus {
        addedData = query[kSecValueData as String] as? Data
        return addStatus
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        XCTAssertEqual(query[kSecAttrService as String] as? String, KeychainService.service)
        updatedData = attributes[kSecValueData as String] as? Data
        return updateStatus
    }

    func randomData(count: Int) -> (status: OSStatus, data: Data) {
        XCTAssertEqual(count, 32)
        return randomResult
    }
}

@MainActor
private final class CoverageServiceManagementAppService: ServiceManagementAppService {
    var status: SMAppService.Status = .notRegistered
    private(set) var transitions: [Bool] = []

    func register() throws {
        transitions.append(true)
        status = .enabled
    }

    func unregister() throws {
        transitions.append(false)
        status = .notRegistered
    }
}
