import AppKit
import Foundation
import Security
import XCTest

@testable import CoreDeckTestHost

final class MasterKeyProviderTests: XCTestCase {
    func testAllConfigurationsUseStableLoginKeychainService() {
        XCTAssertEqual(KeychainService.service, "com.brgirgin.CoreDeck.encryption")
        XCTAssertEqual(KeychainService.legacyService, "com.brgirgin.ClipboardHistory.encryption")
        XCTAssertEqual(KeychainService.account, "history-master-key-v1")
        XCTAssertEqual(KeychainService.notesAccount, "notes-master-key-v1")
        XCTAssertNotEqual(KeychainService.account, KeychainService.notesAccount)
    }

    func testLegacyNotesKeyIsCopiedWithoutChangingOrDeletingOriginal() throws {
        let legacyKey = Data(repeating: 0x42, count: 32)
        let client = MigrationKeychainClient(legacyKey: legacyKey)
        let service = KeychainService(
            client: client,
            account: KeychainService.notesAccount,
            legacyService: KeychainService.legacyService
        )

        XCTAssertEqual(try service.loadOrCreateKey(), legacyKey)
        XCTAssertEqual(try service.loadOrCreateKey(), legacyKey)
        XCTAssertEqual(client.legacyKey, legacyKey)
        XCTAssertEqual(client.currentKey, legacyKey)
        XCTAssertEqual(client.randomCallCount, 0)
    }

    func testLegacyKeyAccessFailureDoesNotGenerateReplacement() {
        let client = MigrationKeychainClient(legacyKey: nil, legacyStatus: errSecAuthFailed)
        let service = KeychainService(
            client: client,
            account: KeychainService.notesAccount,
            legacyService: KeychainService.legacyService
        )

        XCTAssertThrowsError(try service.loadOrCreateKey())
        XCTAssertNil(client.currentKey)
        XCTAssertEqual(client.randomCallCount, 0)
    }

    @MainActor
    func testKeyProviderFailureDoesNotStopOpenClipboardStorage() async {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CoreDeckKeyFailure-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(
            baseDirectory: directory,
            keyProvider: FailingMasterKeyProvider()
        )
        let defaultsName = "CoreDeckKeyFailureDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName) ?? .standard
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let viewModel = CoreDeckViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: NSPasteboard(name: .init(UUID().uuidString))),
            restorePasteboard: NSPasteboard(name: .init(UUID().uuidString)),
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )

        await viewModel.loadHistory()
        viewModel.startMonitoring()

        XCTAssertTrue(viewModel.isStorageAvailable)
        XCTAssertNil(viewModel.errorMessage)
    }
}

private final class MigrationKeychainClient: KeychainSecurityClient {
    let legacyKey: Data?
    let legacyStatus: OSStatus
    private(set) var currentKey: Data?
    private(set) var randomCallCount = 0

    init(legacyKey: Data?, legacyStatus: OSStatus = errSecItemNotFound) {
        self.legacyKey = legacyKey
        self.legacyStatus = legacyStatus
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        let service = query[kSecAttrService as String] as? String
        if service == KeychainService.service {
            return currentKey.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
        }
        if service == KeychainService.legacyService {
            if let legacyKey { return (errSecSuccess, legacyKey) }
            return (legacyStatus, nil)
        }
        return (errSecParam, nil)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        currentKey = query[kSecValueData as String] as? Data
        return currentKey == nil ? errSecParam : errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        errSecUnimplemented
    }

    func randomData(count: Int) -> (status: OSStatus, data: Data) {
        randomCallCount += 1
        return (errSecSuccess, Data(repeating: 0x11, count: count))
    }
}
