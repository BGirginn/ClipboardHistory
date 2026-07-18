import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: ClipboardHistoryViewModel
    private let quickLookService = QuickLookService()
    private var shortcutCancellable: AnyCancellable?
    private var shortcutErrorCancellable: AnyCancellable?
    private lazy var shortcutMonitor = GlobalShortcutMonitor { [weak self] in
        self?.togglePopover()
    }

    init(viewModel: ClipboardHistoryViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Clipboard History"
            )
            button.target = self
            button.action = #selector(togglePopoverFromStatusItem)
            button.toolTip = "Clipboard History (Command-Shift-V)"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPanelView(viewModel: viewModel)
        )

        viewModel.requestClosePanel = { [weak self] in self?.closePopover() }
        viewModel.requestPreview = { [weak self] item in
            guard let self else { return }
            quickLookService.show(item: item, storage: viewModel.storage)
        }
        viewModel.privateModeDidChange = { [weak self] _ in self?.updateStatusIcon() }

        shortcutCancellable = viewModel.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.shortcutMonitor.setEnabled(enabled)
            }
        shortcutMonitor.setEnabled(viewModel.settings.globalShortcutEnabled)
        shortcutErrorCancellable = shortcutMonitor.$registrationError
            .removeDuplicates()
            .sink { [weak viewModel] message in
                viewModel?.setGlobalShortcutError(message)
            }
        updateStatusIcon()
    }

    var isPopoverShown: Bool {
        popover.isShown
    }

    var shortcutRegistrationError: String? {
        shortcutMonitor.registrationError
    }

    func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        viewModel.lockService.recordActivity()
    }

    func closePopover() {
        quickLookService.close()
        popover.performClose(nil)
    }

    func stop() {
        shortcutMonitor.unregister()
        quickLookService.close()
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func popoverWillShow(_ notification: Notification) {
        viewModel.lockService.recordActivity()
    }

    @objc private func togglePopoverFromStatusItem() {
        togglePopover()
    }

    private func updateStatusIcon() {
        let symbol = viewModel.isPrivateMode || viewModel.isPaused ? "eye.slash.fill" : "clipboard"
        let accessibilityDescription: String
        if viewModel.isPaused {
            accessibilityDescription = "Clipboard History recording paused"
        } else if viewModel.isPrivateMode {
            accessibilityDescription = "Clipboard History Private Mode enabled"
        } else {
            accessibilityDescription = "Clipboard History"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        )
        statusItem.button?.toolTip = accessibilityDescription + " (Command-Shift-V)"
    }
}
