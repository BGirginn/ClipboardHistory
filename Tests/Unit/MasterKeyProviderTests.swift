import AppKit
import Foundation
import XCTest

@testable import ClipboardHistory

final class MasterKeyProviderTests: XCTestCase {
    func testAllConfigurationsUseStableLoginKeychainService() {
        XCTAssertEqual(KeychainService.service, "com.brgirgin.ClipboardHistory.encryption")
        XCTAssertEqual(KeychainService.account, "history-master-key-v1")
        XCTAssertEqual(KeychainService.notesAccount, "notes-master-key-v1")
        XCTAssertNotEqual(KeychainService.account, KeychainService.notesAccount)
    }

    @MainActor
    func testKeyProviderFailureStopsViewModelStorage() async {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryKeyFailure-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StorageService(
            baseDirectory: directory,
            keyProvider: FailingMasterKeyProvider()
        )
        let defaultsName = "ClipboardHistoryKeyFailureDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName) ?? .standard
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: NSPasteboard(name: .init(UUID().uuidString))),
            restorePasteboard: NSPasteboard(name: .init(UUID().uuidString)),
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )

        await viewModel.loadHistory()
        viewModel.startMonitoring()

        XCTAssertFalse(viewModel.isStorageAvailable)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
