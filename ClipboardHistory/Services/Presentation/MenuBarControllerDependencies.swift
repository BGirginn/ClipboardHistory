import AppKit
import SwiftUI

@MainActor
struct MenuBarControllerDependencies {
    let makeStatusItem: () -> NSStatusItem
    let removeStatusItem: (NSStatusItem) -> Void
    let makePopover: () -> NSPopover
    let makePanel: (AppModel) -> NSPanel
    let quickLookPresenter: any QuickLookPresenting
    let currentEvent: () -> NSEvent?
    let presentStatusMenu: (NSMenu, NSView) -> Void
    let terminateApplication: () -> Void

    init(
        makeStatusItem: @escaping () -> NSStatusItem,
        removeStatusItem: @escaping (NSStatusItem) -> Void = NSStatusBar.system.removeStatusItem,
        makePopover: @escaping () -> NSPopover,
        makePanel: @escaping (AppModel) -> NSPanel,
        quickLookPresenter: any QuickLookPresenting,
        currentEvent: @escaping () -> NSEvent? = { NSApplication.shared.currentEvent },
        presentStatusMenu: @escaping (NSMenu, NSView) -> Void = { menu, view in
            _ = menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: view.bounds.maxY),
                in: view
            )
        },
        terminateApplication: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.makeStatusItem = makeStatusItem
        self.removeStatusItem = removeStatusItem
        self.makePopover = makePopover
        self.makePanel = makePanel
        self.quickLookPresenter = quickLookPresenter
        self.currentEvent = currentEvent
        self.presentStatusMenu = presentStatusMenu
        self.terminateApplication = terminateApplication
    }

    static func resolve(for model: AppModel, provided: MenuBarControllerDependencies?) -> MenuBarControllerDependencies {
        if let provided { return provided }
        #if CLIPBOARD_HISTORY_TEST_HOST
        if let root = model.uiTestRoot { return .isolated(temporaryRoot: root) }
        #endif
        return .live
    }

    static func resolveShortcut(for model: AppModel, provided: (any GlobalShortcutBackend)?) -> any GlobalShortcutBackend {
        if let provided { return provided }
        #if CLIPBOARD_HISTORY_TEST_HOST
        if model.uiTestRoot != nil { return UITestSystemServices() }
        #endif
        return SystemGlobalShortcutBackend()
    }

    static var live: MenuBarControllerDependencies {
        make(quickLookPresenter: QuickLookService())
    }

    static func isolated(temporaryRoot: URL) -> MenuBarControllerDependencies {
        make(quickLookPresenter: QuickLookService(panelProvider: { nil }, temporaryDirectoryProvider: { temporaryRoot }))
    }

    private static func make(quickLookPresenter: any QuickLookPresenting) -> MenuBarControllerDependencies {
        MenuBarControllerDependencies(
            makeStatusItem: {
                NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            },
            makePopover: NSPopover.init,
            makePanel: { model in
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                    styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "Clipboard History"
                panel.isReleasedWhenClosed = false
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentMinSize = NSSize(width: 340, height: 420)
                panel.contentMaxSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
                panel.contentViewController = NSHostingController(
                    rootView: AppShellView(model: model)
                )
                return panel
            },
            quickLookPresenter: quickLookPresenter
        )
    }
}
