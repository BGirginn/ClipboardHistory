import AppKit
import SwiftUI

@MainActor
final class ApplicationWindowController: NSObject, ApplicationWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = "ClipboardHistory.MainWindow"

    private let appModel: AppModel
    private var applicationWindow: NSWindow?
    private var pendingCloseTask: Task<Void, Never>?
    private var allowsPendingClose = false

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
    }

    var isWindowVisible: Bool {
        applicationWindow?.isVisible == true
    }

    func showControlCenter() {
        appModel.prepareForNormalPresentation()
        showWindow()
    }

    func showActiveFeature() {
        showWindow()
    }

    func stop() {
        pendingCloseTask?.cancel()
        pendingCloseTask = nil
        applicationWindow?.delegate = nil
        applicationWindow?.close()
        applicationWindow = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsPendingClose {
            allowsPendingClose = false
            return true
        }
        guard appModel.router.activeFeature == .notes,
              appModel.notes.hasPendingChanges else { return true }
        guard pendingCloseTask == nil else { return false }

        pendingCloseTask = Task { [weak self, weak sender] in
            guard let self else { return }
            let outcome = await appModel.notes.flushPendingSave()
            if outcome.allowsTransition, let sender {
                allowsPendingClose = true
                sender.performClose(nil)
            }
            pendingCloseTask = nil
        }
        return false
    }

    private func showWindow() {
        let window = ensureWindow()
        appModel.clipboard.capturePasteTargetApplication()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let applicationWindow { return applicationWindow }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipboardHistory"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(
            width: AppDesign.panelMinimumWidth,
            height: AppDesign.panelMinimumHeight
        )
        window.contentViewController = NSHostingController(
            rootView: AppShellView(model: appModel)
        )
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.delegate = self
        applicationWindow = window
        return window
    }
}
