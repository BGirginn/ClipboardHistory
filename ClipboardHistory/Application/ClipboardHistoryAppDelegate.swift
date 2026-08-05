import AppKit
import Foundation

@MainActor
final class ClipboardHistoryAppDelegate: NSObject, NSApplicationDelegate {
    typealias ViewModelFactory = @MainActor () -> ClipboardHistoryViewModel
    typealias MenuBarControllerFactory = @MainActor (ClipboardHistoryViewModel) -> MenuBarController

    private let environment: [String: String]
    private let viewModelFactory: ViewModelFactory
    private let menuBarControllerFactory: MenuBarControllerFactory
    private var viewModel: ClipboardHistoryViewModel?
    private var menuBarController: MenuBarController?
    private var terminationTask: Task<Void, Never>?
    #if DEBUG
    private var uiTestAnchorWindow: NSWindow?
    #endif

    override convenience init() {
        self.init(
            environment: ProcessInfo.processInfo.environment,
            viewModelFactory: { ClipboardHistoryViewModel() },
            menuBarControllerFactory: { MenuBarController(viewModel: $0) }
        )
    }

    init(
        environment: [String: String],
        viewModelFactory: @escaping ViewModelFactory,
        menuBarControllerFactory: @escaping MenuBarControllerFactory
    ) {
        self.environment = environment
        self.viewModelFactory = viewModelFactory
        self.menuBarControllerFactory = menuBarControllerFactory
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        guard environment["XCTestConfigurationFilePath"] == nil else {
            AppLog.lifecycle.debug("Application services disabled for hosted unit tests")
            return
        }
        #endif
        #if DEBUG
        if environment["CLIPBOARD_HISTORY_UI_TESTING"] == "1" {
            launchForUITesting()
            return
        }
        #endif
        let viewModel = viewModelFactory()
        self.viewModel = viewModel
        menuBarController = menuBarControllerFactory(viewModel)
        AppLog.lifecycle.notice("Application launched; interface=menu-bar")
    }

    #if DEBUG
    private func launchForUITesting() {
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
        let anchorWindow = makeUITestAnchorWindow()
        uiTestAnchorWindow = anchorWindow
        let controller = MenuBarController(viewModel: viewModel) { [weak anchorWindow] in
            anchorWindow?.contentView
        }
        menuBarController = controller
        Task {
            await viewModel.loadHistory()
            if viewModel.items.isEmpty {
                await viewModel.insert(.text(value: "Alpha clipboard item", hash: "ui-alpha"))
                await viewModel.insert(.text(value: "Beta clipboard item", hash: "ui-beta"))
                await viewModel.insert(.text(value: "Gamma clipboard item", hash: "ui-gamma"))
            }
            if viewModel.collections.isEmpty {
                let collection = ClipboardCollection(name: "Coverage Collection")
                try? await viewModel.storage.upsertCollection(collection)
                viewModel.collections = [collection]
            }
            controller.showPopover()
        }
        AppLog.lifecycle.notice("Application launched; interface=isolated-ui-test")
    }

    private func makeUITestAnchorWindow() -> NSWindow {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: 1, y: 1)) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1, height: 1)
        let window = NSWindow(
            contentRect: NSRect(
                x: visibleFrame.midX,
                y: visibleFrame.maxY - 1,
                width: 1,
                height: 1
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        return window
    }
    #endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { [weak self, weak sender] in
            await viewModel.shutdown()
            self?.menuBarController?.stop()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if terminationTask == nil {
            viewModel?.prepareForShutdown()
        }
        terminationTask?.cancel()
        terminationTask = nil
        menuBarController?.stop()
        menuBarController = nil
        #if DEBUG
        uiTestAnchorWindow?.close()
        uiTestAnchorWindow = nil
        #endif
        viewModel = nil
    }
}
