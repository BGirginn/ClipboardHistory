import AppKit
import Foundation

@main
@MainActor
enum ClipboardHistoryMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ClipboardHistoryAppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class ClipboardHistoryAppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: ClipboardHistoryViewModel?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            AppLog.lifecycle.debug("Application services disabled for hosted unit tests")
            return
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLIPBOARD_HISTORY_UI_TESTING"] == "1" {
            launchForUITesting()
            return
        }
        #endif
        let viewModel = ClipboardHistoryViewModel()
        self.viewModel = viewModel
        menuBarController = MenuBarController(viewModel: viewModel)
        AppLog.lifecycle.notice("Application launched; interface=menu-bar")
    }

    #if DEBUG
    private func launchForUITesting() {
        let environment = ProcessInfo.processInfo.environment
        let requestedRoot = environment["CLIPBOARD_HISTORY_TEST_ROOT"].map(
            URL.init(fileURLWithPath:)
        )
        let fallbackRoot = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistory-UITesting-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let root = requestedRoot?.standardizedFileURL.path.hasPrefix("/private/tmp/") == true
            ? requestedRoot ?? fallbackRoot
            : fallbackRoot
        let suiteName = environment["CLIPBOARD_HISTORY_TEST_DEFAULTS"]
            ?? "ClipboardHistory.UITesting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(false, forKey: "closePanelAfterCopying")
        defaults.set(1, forKey: "closePanelAfterCopyingMigrationVersion")
        let pasteboard = NSPasteboard(
            name: .init("ClipboardHistory.UITesting.\(UUID().uuidString)")
        )
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: root, encryptionService: .ephemeral()),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )
        self.viewModel = viewModel
        let controller = MenuBarController(viewModel: viewModel)
        menuBarController = controller
        Task {
            await viewModel.loadHistory()
            if viewModel.items.isEmpty {
                await viewModel.insert(.text(value: "Alpha clipboard item", hash: "ui-alpha"))
                await viewModel.insert(.text(value: "Beta clipboard item", hash: "ui-beta"))
                await viewModel.insert(.text(value: "Gamma clipboard item", hash: "ui-gamma"))
            }
            controller.showPopover()
        }
        AppLog.lifecycle.notice("Application launched; interface=isolated-ui-test")
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.prepareForShutdown()
        menuBarController?.stop()
        menuBarController = nil
        viewModel = nil
    }
}
