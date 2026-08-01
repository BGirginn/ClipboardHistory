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
        let panel = dependencies.makePanel(context.viewModel)

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
            viewModel: context.viewModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )
        popover.animates = false
        panel.animationBehavior = .none

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
        XCTAssertEqual(statusItem.button?.toolTip, "Clipboard History (Command-Shift-V)")
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
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: { statusItem },
            makePopover: { popover },
            makePanel: { _ in panel },
            quickLookPresenter: MenuQuickLookSpy()
        )
        let controller = MenuBarController(
            viewModel: context.viewModel,
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
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertTrue(popover.isShown)
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertFalse(popover.isShown)

        context.settings.shortcutActivationMode = .hold
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        controller.closePopover()

        statusItem.button?.performClick(nil)
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
        XCTAssertTrue(panel.isVisible)
        for edge in PanelScreenEdge.allCases {
            context.settings.panelScreenEdge = edge
            controller.positionDetachablePanel()
        }
        controller.togglePopover()
        XCTAssertFalse(panel.isVisible)

        controller.stop()
        await cleanup(context)
    }

    private struct Context {
        let directory: URL
        let suite: String
        let storage: StorageService
        let settings: AppSettings
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
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: MenuPasteServiceStub(),
            settings: settings,
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            suite: suite,
            storage: storage,
            settings: settings,
            viewModel: viewModel
        )
    }

    private func cleanup(_ context: Context) async {
        context.viewModel.prepareForShutdown()
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
