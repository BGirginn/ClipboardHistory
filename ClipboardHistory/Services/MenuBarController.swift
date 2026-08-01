import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let dependencies: MenuBarControllerDependencies
    private let popoverAnchor: (() -> NSView?)?
    private var detachablePanel: NSPanel?
    private let viewModel: ClipboardHistoryViewModel
    private let quickLookService: any QuickLookPresenting
    private let shortcutBackend: any GlobalShortcutBackend
    private var shortcutCancellable: AnyCancellable?
    private var shortcutPresetCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var panelEdgeCancellable: AnyCancellable?
    private var shortcutErrorCancellable: AnyCancellable?
    private var panelCloseCoordinator: PanelCloseCoordinator!
    private lazy var shortcutMonitor = GlobalShortcutMonitor(
        action: { [weak self] in self?.shortcutPressed() },
        releaseAction: { [weak self] in self?.shortcutReleased() },
        backend: shortcutBackend
    )

    init(
        viewModel: ClipboardHistoryViewModel,
        dependencies: MenuBarControllerDependencies = .live,
        panelEventMonitor: any PanelEventMonitoring = SystemPanelEventMonitor(),
        shortcutBackend: any GlobalShortcutBackend = SystemGlobalShortcutBackend(),
        popoverAnchor: (() -> NSView?)? = nil
    ) {
        self.viewModel = viewModel
        self.dependencies = dependencies
        self.shortcutBackend = shortcutBackend
        self.popoverAnchor = popoverAnchor
        statusItem = dependencies.makeStatusItem()
        popover = dependencies.makePopover()
        quickLookService = dependencies.quickLookPresenter
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Clipboard History"
            )
            button.target = self
            button.action = #selector(handleStatusItemAction)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityHelp("Left-click to open Clipboard History. Right-click to quit.")
            button.toolTip = "Clipboard History (Command-Shift-V, right-click to quit)"
        }

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 500)
        panelCloseCoordinator = PanelCloseCoordinator(
            eventMonitor: panelEventMonitor,
            isPanelShown: { [weak self] in self?.popover.isShown == true },
            isPanelEvent: { [weak self] event in
                event.window === self?.popover.contentViewController?.view.window
            },
            isStatusItemEvent: { [weak self] event in self?.isStatusItemEvent(event) == true },
            closePanel: { [weak self] in self?.closePopover() }
        )
        viewModel.requestClosePanel = { [weak self] in self?.closePopover() }
        viewModel.menuCommandDidRun = { [weak self] in
            self?.panelCloseCoordinator.menuCommandDidRun()
        }
        viewModel.requestPreview = { [weak self] item in
            guard let self else { return }
            quickLookService.show(item: item, storage: viewModel.storage)
        }
        viewModel.privateModeDidChange = { [weak self] _ in self?.updateStatusIcon() }

        shortcutCancellable = viewModel.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                shortcutMonitor.setEnabled(
                    enabled,
                    shortcut: viewModel.settings.globalShortcut
                )
            }
        shortcutPresetCancellable = viewModel.settings.$globalShortcutPresetID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                shortcutMonitor.setEnabled(
                    viewModel.settings.globalShortcutEnabled,
                    shortcut: viewModel.settings.globalShortcut
                )
            }
        shortcutMonitor.setEnabled(
            viewModel.settings.globalShortcutEnabled,
            shortcut: viewModel.settings.globalShortcut
        )
        shortcutErrorCancellable = shortcutMonitor.$registrationError
            .removeDuplicates()
            .sink { [weak viewModel] message in
                viewModel?.setGlobalShortcutError(message)
            }
        appearanceCancellable = viewModel.settings.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
        panelEdgeCancellable = viewModel.settings.$panelScreenEdge
            .removeDuplicates()
            .sink { [weak self] _ in self?.positionDetachablePanel() }
        updateStatusIcon()
    }

    var isPopoverShown: Bool {
        popover.isShown || detachablePanel?.isVisible == true
    }

    var shortcutRegistrationError: String? {
        shortcutMonitor.registrationError
    }

    func togglePopover() {
        isPopoverShown ? closePopover() : showPopover()
    }

    func showPopover() {
        viewModel.prepareForPanelPresentation()
        if viewModel.settings.panelPresentationMode == .detachable {
            showDetachablePanel()
            return
        }
        guard let anchor = popoverAnchor?() ?? statusItem.button else { return }
        ensurePopoverContent()
        viewModel.capturePasteTargetApplication()
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        viewModel.lockService.recordActivity()
    }

    func closePopover() {
        shortcutMonitor.cancelHeldShortcut()
        quickLookService.close()
        popover.performClose(nil)
        detachablePanel?.orderOut(nil)
    }

    func stop() {
        panelCloseCoordinator.stop()
        shortcutMonitor.cancelHeldShortcut()
        shortcutMonitor.unregister()
        quickLookService.close()
        popover.close()
        detachablePanel?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func popoverWillShow(_ notification: Notification) {
        panelCloseCoordinator.start()
        viewModel.lockService.recordActivity()
    }

    @objc private func handleStatusItemAction() {
        if dependencies.currentEvent()?.type == .rightMouseUp {
            dependencies.terminateApplication()
        } else {
            togglePopover()
        }
    }

    private func shortcutPressed() {
        switch viewModel.settings.shortcutActivationMode {
        case .toggle:
            togglePopover()
        case .hold:
            if !popover.isShown { showPopover() }
        }
    }

    private func shortcutReleased() {
        guard viewModel.settings.shortcutActivationMode == .hold,
              popover.isShown else { return }
        viewModel.pasteSelectedToActiveApp()
    }

    private func showDetachablePanel() {
        let panel = ensureDetachablePanel()
        viewModel.capturePasteTargetApplication()
        NSApp.activate()
        positionDetachablePanel()
        panel.makeKeyAndOrderFront(nil)
        viewModel.lockService.recordActivity()
    }

    func isStatusItemEvent(_ event: NSEvent) -> Bool {
        event.window === statusItem.button?.window
    }

    func positionDetachablePanel() {
        guard let detachablePanel,
              detachablePanel.isVisible || viewModel.settings.panelPresentationMode == .detachable,
              let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = detachablePanel.frame.size
        let margin: CGFloat = 12
        let origin: NSPoint
        switch viewModel.settings.panelScreenEdge {
        case .left:
            origin = NSPoint(x: visible.minX + margin, y: visible.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
        case .bottom:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + margin)
        }
        detachablePanel.setFrameOrigin(origin)
    }

    private func ensurePopoverContent() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPanelView(viewModel: viewModel)
        )
    }

    private func ensureDetachablePanel() -> NSPanel {
        if let detachablePanel { return detachablePanel }
        let panel = dependencies.makePanel(viewModel)
        detachablePanel = panel
        applyAppearance(viewModel.settings.appearance)
        return panel
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        let name: NSAppearance.Name?
        switch appearance {
        case .system: name = nil
        case .light: name = .aqua
        case .dark: name = .darkAqua
        }
        let resolvedAppearance = name.flatMap { NSAppearance(named: $0) }
        popover.appearance = resolvedAppearance
        detachablePanel?.appearance = resolvedAppearance
    }

    private func updateStatusIcon() {
        let symbol = viewModel.isPrivateMode || viewModel.isPaused ? "eye.slash.fill" : "clipboard"
        let accessibilityDescription: String
        if viewModel.isPrivateMode {
            accessibilityDescription = "Clipboard History Private Mode enabled"
        } else if viewModel.isPaused {
            accessibilityDescription = "Clipboard History recording paused"
        } else {
            accessibilityDescription = "Clipboard History"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        )
        statusItem.button?.toolTip = accessibilityDescription + " (Command-Shift-V, right-click to quit)"
    }
}
