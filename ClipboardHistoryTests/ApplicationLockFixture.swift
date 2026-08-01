import AppKit
import Foundation
@testable import ClipboardHistory

@MainActor
struct ApplicationLockFixture {
    let directory: URL
    let suite: String
    let defaults: UserDefaults
    let settings: AppSettings
    let storage: StorageService
    let pasteboard: NSPasteboard
    let viewModel: ClipboardHistoryViewModel

    func cleanup() {
        viewModel.prepareForShutdown()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
