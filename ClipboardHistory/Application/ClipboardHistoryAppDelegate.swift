import AppKit
import Foundation

@MainActor
final class ClipboardHistoryAppDelegate: NSObject, NSApplicationDelegate {
    typealias AppModelFactory = @MainActor () -> AppModel
    typealias MenuBarControllerFactory = @MainActor (AppModel) -> MenuBarController
    typealias TerminationReply = @MainActor (NSApplication, Bool) -> Void

    private let environment: [String: String]
    private let arguments: [String]
    private let appModelFactory: AppModelFactory
    private let menuBarControllerFactory: MenuBarControllerFactory
    private let terminationReply: TerminationReply
    private var appModel: AppModel?
    private var menuBarController: MenuBarController?
    private var terminationTask: Task<Void, Never>?
    #if DEBUG
    private var uiTestAnchorWindow: NSWindow?
    #endif

    override convenience init() {
        self.init(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments,
            appModelFactory: { AppModel() },
            menuBarControllerFactory: { MenuBarController(appModel: $0) },
            terminationReply: { $0.reply(toApplicationShouldTerminate: $1) }
        )
    }

    init(
        environment: [String: String],
        arguments: [String] = [],
        appModelFactory: @escaping AppModelFactory,
        menuBarControllerFactory: @escaping MenuBarControllerFactory,
        terminationReply: @escaping TerminationReply = {
            $0.reply(toApplicationShouldTerminate: $1)
        }
    ) {
        self.environment = environment
        self.arguments = arguments
        self.appModelFactory = appModelFactory
        self.menuBarControllerFactory = menuBarControllerFactory
        self.terminationReply = terminationReply
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if environment["CLIPBOARD_HISTORY_UI_TESTING"] == "1" {
            launchForUITesting()
            return
        }
        guard environment["XCTestConfigurationFilePath"] == nil else {
            AppLog.lifecycle.debug("Application services disabled for hosted unit tests")
            return
        }
        #endif
        let appModel = appModelFactory()
        self.appModel = appModel
        let controller = menuBarControllerFactory(appModel)
        menuBarController = controller
        if !arguments.contains("--background-launch") {
            Task { @MainActor in
                await Task.yield()
                controller.showControlCenter()
            }
        }
        AppLog.lifecycle.notice("Application launched; interface=menu-bar")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        menuBarController?.showControlCenter()
        return false
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
        let appModel = AppModel(
            storage: StorageService(baseDirectory: root, encryptionService: .ephemeral()),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            audioMixerController: AudioMixerController(defaults: defaults),
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: defaults)
            ),
            startsAutomatically: false
        )
        appModel.controlCenter.setShownInControlCenter(true, for: .audioMixer)
        self.appModel = appModel
        let anchorWindow = makeUITestAnchorWindow()
        uiTestAnchorWindow = anchorWindow
        let controller = MenuBarController(appModel: appModel) { [weak anchorWindow] in
            anchorWindow?.contentView
        }
        menuBarController = controller
        let seedItems = [
            ClipboardItem(type: .text, text: "Alpha clipboard item", hash: "ui-alpha"),
            ClipboardItem(type: .text, text: "Beta clipboard item", hash: "ui-beta"),
            ClipboardItem(type: .text, text: "Gamma clipboard item", hash: "ui-gamma")
        ]
        let seedCollection = ClipboardCollection(name: "Coverage Collection")
        appModel.clipboard.items = seedItems
        appModel.clipboard.collections = [seedCollection]
        appModel.clipboard.refreshDisplayedItems()
        controller.showPopover()
        Task {
            for item in seedItems {
                try? await appModel.clipboard.storage.upsertThrowing(item)
            }
            try? await appModel.clipboard.storage.upsertCollection(seedCollection)
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
        guard let appModel else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        let terminationReply = terminationReply
        terminationTask = Task { [weak self, weak sender] in
            let outcome = await appModel.shutdown()
            let canTerminate = outcome.allowsTermination
            guard let self else {
                if let sender {
                    terminationReply(sender, canTerminate)
                }
                return
            }
            if canTerminate {
                menuBarController?.stop()
                if let sender { terminationReply(sender, true) }
            } else {
                terminationTask = nil
                menuBarController?.showActiveFeature()
                if let sender { terminationReply(sender, false) }
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if terminationTask == nil {
            appModel?.prepareForShutdown()
        }
        terminationTask?.cancel()
        terminationTask = nil
        menuBarController?.stop()
        menuBarController = nil
        #if DEBUG
        uiTestAnchorWindow?.close()
        uiTestAnchorWindow = nil
        #endif
        appModel = nil
    }
}
