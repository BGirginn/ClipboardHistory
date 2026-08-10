import AppKit
import Carbon
import XCTest

@testable import ClipboardHistory

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testLiveDependenciesCreateConfiguredAppKitObjects() async {
        let context = makeContext()
        let dependencies = MenuBarControllerDependencies.live
        let statusItem = dependencies.makeStatusItem()
        let popover = dependencies.makePopover()
        let panel = dependencies.makePanel(context.appModel)

        XCTAssertNotNil(statusItem.button)
        XCTAssertEqual(panel.title, "Clipboard History")
        XCTAssertEqual(panel.contentMinSize, NSSize(width: 340, height: 420))
        XCTAssertNotNil(panel.contentViewController)
        dependencies.quickLookPresenter.close()

        popover.close()
        panel.close()
        NSStatusBar.system.removeStatusItem(statusItem)
        await cleanup(context)
    }

    func testControllerCallbacksModesCloseAndStopWithoutAnimatingAppKitWindows() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let popover = NSPopover()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let quickLook = MenuQuickLookSpy()
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: { statusItem },
            makePopover: { popover },
            makePanel: { _ in panel },
            quickLookPresenter: quickLook
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )
        XCTAssertTrue(popover.animates)
        XCTAssertNotNil(popover.contentViewController)
        panel.animationBehavior = .none

        context.settings.appearance = .light
        XCTAssertEqual(popover.appearance?.name, .aqua)
        context.settings.appearance = .dark
        XCTAssertEqual(popover.appearance?.name, .darkAqua)
        context.settings.appearance = .system
        XCTAssertNil(popover.appearance)

        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertNil(controller.shortcutRegistrationError)
        controller.popoverWillShow(Notification(name: NSPopover.willShowNotification))
        context.viewModel.menuCommandDidRun?()
        let preview = ClipboardItem(type: .text, text: "preview", hash: "preview")
        context.viewModel.requestPreview?(preview)
        XCTAssertEqual(quickLook.shownItems, [preview])
        context.viewModel.setPrivateModeEnabled(true)
        XCTAssertTrue(statusItem.button?.toolTip?.contains("Private Mode") == true)
        context.viewModel.setPrivateModeEnabled(false)
        context.viewModel.pauseUntil = .now.addingTimeInterval(60)
        context.viewModel.privateModeDidChange?(false)
        XCTAssertTrue(statusItem.button?.toolTip?.contains("paused") == true)
        context.viewModel.pauseUntil = nil
        context.viewModel.isPrivateMode = false
        context.viewModel.privateModeDidChange?(false)
        XCTAssertEqual(
            statusItem.button?.toolTip,
            "ClipboardHistory Control Center — right-click for options"
        )
        controller.closePopover()
        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertGreaterThanOrEqual(quickLook.closeCount, 1)

        context.settings.panelPresentationMode = .detachable
        for edge in PanelScreenEdge.allCases {
            context.settings.panelScreenEdge = edge
        }

        controller.stop()
        XCTAssertGreaterThanOrEqual(quickLook.closeCount, 2)
        await cleanup(context)
    }

    func testPopoverDetachableStatusActionShortcutAndPublisherCallbacks() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        await context.viewModel.insert(.text(value: "shortcut", hash: "shortcut"))
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let popover = MenuPopoverStub()
        let panel = MenuPanelStub()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let eventMonitor = MenuRecordingPanelEventMonitor()
        let shortcutBackend = MenuShortcutBackendStub()
        var statusItemEvent: NSEvent?
        var presentedStatusMenu: NSMenu?
        var terminationCount = 0
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: { statusItem },
            makePopover: { popover },
            makePanel: { _ in panel },
            quickLookPresenter: MenuQuickLookSpy(),
            currentEvent: { statusItemEvent },
            presentStatusMenu: { menu, _ in presentedStatusMenu = menu },
            terminateApplication: { terminationCount += 1 }
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: eventMonitor,
            shortcutBackend: shortcutBackend,
            popoverAnchor: { anchor }
        )

        context.settings.globalShortcutPresetID = GlobalShortcut.presets[1].id
        context.settings.globalShortcutEnabled = true
        XCTAssertGreaterThanOrEqual(shortcutBackend.installCount, 1)
        XCTAssertGreaterThanOrEqual(shortcutBackend.registerCount, 1)

        context.settings.shortcutActivationMode = .toggle
        context.appModel.router.openSettings()
        context.viewModel.detailItem = context.viewModel.items.first
        context.viewModel.searchText = "stale presentation"
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertTrue(popover.isShown, "Global shortcut should show the clipboard popover")
        XCTAssertEqual(context.appModel.router.activeFeature, .clipboard)
        XCTAssertNil(context.viewModel.detailItem)
        XCTAssertEqual(context.viewModel.searchText, "")
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertFalse(popover.isShown)

        context.settings.shortcutActivationMode = .hold
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        controller.closePopover()

        statusItem.button?.performClick(nil)
        await Task.yield()
        XCTAssertTrue(popover.isShown, "Control Center status item should show the popover")
        statusItemEvent = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        statusItem.button?.performClick(nil)
        XCTAssertEqual(
            presentedStatusMenu?.items.map(\.title),
            [
                "Customize Menu Bar",
                "",
                "Open Control Center",
                "Open Settings",
                "",
                "Quit ClipboardHistory"
            ]
        )
        XCTAssertEqual(terminationCount, 0)
        presentedStatusMenu?.performActionForItem(at: 5)
        XCTAssertEqual(terminationCount, 1)
        statusItemEvent = nil
        let event = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )
        )
        _ = eventMonitor.fireLocal(event)
        _ = controller.isStatusItemEvent(event)
        controller.closePopover()

        context.settings.panelPresentationMode = .detachable
        controller.showPopover()
        XCTAssertTrue(panel.isVisible, "Detachable presentation should show its panel")
        for edge in PanelScreenEdge.allCases {
            context.settings.panelScreenEdge = edge
            controller.positionDetachablePanel()
        }
        controller.togglePopover()
        XCTAssertFalse(panel.isVisible)

        controller.stop()
        await cleanup(context)
    }

    func testConfigurationAddsAndRemovesStandaloneStatusItemsWithoutRestart() async {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        var createdItems: [NSStatusItem] = []
        var removedItems: [NSStatusItem] = []
        var currentEvent: NSEvent?
        var presentedMenu: NSMenu?
        let popover = MenuPopoverStub()
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                createdItems.append(item)
                return item
            },
            removeStatusItem: { item in
                removedItems.append(item)
                NSStatusBar.system.removeStatusItem(item)
            },
            makePopover: { popover },
            makePanel: { _ in MenuPanelStub() },
            quickLookPresenter: MenuQuickLookSpy(),
            currentEvent: { currentEvent },
            presentStatusMenu: { menu, _ in presentedMenu = menu }
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        XCTAssertEqual(createdItems.count, 1)
        XCTAssertEqual(createdItems.first?.autosaveName, "ClipboardHistory.ControlCenter")

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .notes)
        XCTAssertEqual(createdItems.count, 2)
        XCTAssertEqual(createdItems.last?.autosaveName, "ClipboardHistory.Feature.notes")

        controller.showControlCenter()
        XCTAssertTrue(popover.isShown)
        context.appModel.controlCenter.setControlCenterItemVisible(false)
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(controller.activeAnchorID, .feature(.notes))
        XCTAssertEqual(removedItems.count, 1)

        currentEvent = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        createdItems.last?.button?.performClick(nil)
        XCTAssertEqual(
            presentedMenu?.items.map(\.title),
            [
                "Open Module",
                "New Note",
                "",
                "Notes",
                "",
                "Open Control Center",
                "Open Settings",
                "",
                "Quit ClipboardHistory"
            ]
        )

        context.appModel.controlCenter.setStandaloneItemVisible(false, for: .notes)
        XCTAssertEqual(removedItems.count, 2)
        XCTAssertEqual(createdItems.count, 3)
        XCTAssertEqual(controller.activeAnchorID, .controlCenter)
        XCTAssertTrue(popover.isShown)

        controller.stop()
        XCTAssertEqual(removedItems.count, 3)
        await cleanup(context)
    }

    private struct Context {
        let directory: URL
        let suite: String
        let storage: StorageService
        let settings: AppSettings
        let appModel: AppModel
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext() -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "MenuBarControllerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suite = "MenuBarControllerDefaults-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("MenuBarController-\(UUID().uuidString)"))
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: MenuPasteServiceStub(),
            settings: settings,
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: UserDefaults(suiteName: suite)!)
            ),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            suite: suite,
            storage: storage,
            settings: settings,
            appModel: appModel,
            viewModel: appModel.clipboard
        )
    }

    private func cleanup(_ context: Context) async {
        context.appModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.suite)
        try? FileManager.default.removeItem(at: context.directory)
    }

}

@MainActor
private final class MenuPopoverStub: NSPopover {
    private var presented = false

    override var isShown: Bool { presented }

    override func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        presented = true
        delegate?.popoverWillShow?(Notification(name: NSPopover.willShowNotification, object: self))
    }

    override func performClose(_ sender: Any?) {
        presented = false
    }

    override func close() {
        presented = false
    }
}

@MainActor
private final class MenuPanelStub: NSPanel {
    private var presented = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override var isVisible: Bool { presented }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        presented = true
    }

    override func orderOut(_ sender: Any?) {
        presented = false
    }

    override func close() {
        presented = false
    }

    override func setFrameOrigin(_ point: NSPoint) {}
}

@MainActor
private final class MenuQuickLookSpy: QuickLookPresenting {
    private(set) var shownItems: [ClipboardItem] = []
    private(set) var closeCount = 0

    func show(item: ClipboardItem, storage: StorageService) {
        shownItems.append(item)
    }

    func close() {
        closeCount += 1
    }
}

@MainActor
private final class MenuPasteServiceStub: ActiveApplicationPasting {
    func captureTargetApplication() {}
    func paste() async -> ActiveApplicationPasteResult { .pasted }
}

@MainActor
private final class MenuPanelEventMonitorStub: PanelEventMonitoring {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { nil }
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    func removeMonitor(_ monitor: Any) {}
}

@MainActor
private final class MenuRecordingPanelEventMonitor: PanelEventMonitoring {
    private var localHandler: ((NSEvent) -> NSEvent?)?

    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { NSObject() }

    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localHandler = handler
        return NSObject()
    }

    func removeMonitor(_ monitor: Any) {}

    func fireLocal(_ event: NSEvent) -> NSEvent? {
        localHandler?(event)
    }
}

@MainActor
private final class MenuShortcutBackendStub: GlobalShortcutBackend {
    var eventAction: ((UInt32) -> Void)?
    private(set) var installCount = 0
    private(set) var registerCount = 0

    func installEventHandler() -> OSStatus {
        installCount += 1
        return noErr
    }

    func register(shortcut: GlobalShortcut) -> OSStatus {
        registerCount += 1
        return noErr
    }

    func unregister() {}

    func fire(_ kind: UInt32) {
        eventAction?(kind)
    }
}
