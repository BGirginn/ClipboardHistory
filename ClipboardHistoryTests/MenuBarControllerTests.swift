import AppKit
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
