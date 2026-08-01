import AppKit
import SwiftUI

@MainActor
struct MenuBarControllerDependencies {
    let makeStatusItem: () -> NSStatusItem
    let makePopover: () -> NSPopover
    let makePanel: (ClipboardHistoryViewModel) -> NSPanel
    let quickLookPresenter: any QuickLookPresenting
    let currentEvent: () -> NSEvent?
    let terminateApplication: () -> Void

    init(
        makeStatusItem: @escaping () -> NSStatusItem,
        makePopover: @escaping () -> NSPopover,
        makePanel: @escaping (ClipboardHistoryViewModel) -> NSPanel,
        quickLookPresenter: any QuickLookPresenting,
        currentEvent: @escaping () -> NSEvent? = { NSApplication.shared.currentEvent },
        terminateApplication: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.makeStatusItem = makeStatusItem
        self.makePopover = makePopover
        self.makePanel = makePanel
        self.quickLookPresenter = quickLookPresenter
        self.currentEvent = currentEvent
        self.terminateApplication = terminateApplication
    }

    static var live: MenuBarControllerDependencies {
        MenuBarControllerDependencies(
            makeStatusItem: {
                NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            },
            makePopover: NSPopover.init,
            makePanel: { viewModel in
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
                panel.contentViewController = NSHostingController(
                    rootView: ClipboardPanelView(viewModel: viewModel)
                )
                return panel
            },
            quickLookPresenter: QuickLookService()
        )
    }
}
