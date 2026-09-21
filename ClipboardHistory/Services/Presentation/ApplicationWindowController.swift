import AppKit
import Combine
import SwiftUI

@MainActor
final class ApplicationWindowController: NSObject, ApplicationWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = "ClipboardHistory.MainWindow"

    private let appModel: AppModel
    private let makeWindow: () -> NSWindow
    private let makeContentViewController: (AppModel) -> NSViewController
    private var applicationWindow: NSWindow?
    private var pendingCloseTask: Task<Void, Never>?
    private var allowsPendingClose = false
    private let demandSource = SamplingDemandSource()
    private var routeCancellable: AnyCancellable?
    private var settingsSubsectionCancellable: AnyCancellable?

    init(
        appModel: AppModel,
        makeWindow: @escaping () -> NSWindow = {
            NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        },
        makeContentViewController: @escaping (AppModel) -> NSViewController = {
            NSHostingController(rootView: AppShellView(model: $0, isWindow: true))
        }
    ) {
        self.appModel = appModel
        self.makeWindow = makeWindow
        self.makeContentViewController = makeContentViewController
        super.init()
        routeCancellable = appModel.router.$activeFeature
            .removeDuplicates()
            .sink { [weak self] feature in
                guard let self else { return }
                self.appModel.updatePresentationDemand(
                    for: self.demandSource,
                    isVisible: self.isWindowVisible,
                    presentedFeature: feature
                )
            }
        settingsSubsectionCancellable = appModel.router.$settingsSubsection
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self,
                          self.appModel.router.activeFeature == .settings else { return }
                    self.appModel.updatePresentationDemand(
                        for: self.demandSource,
                        isVisible: self.isWindowVisible
                    )
                }
            }
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
        appModel.updatePresentationDemand(for: demandSource, isVisible: false)
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
            let outcome = await self.appModel.notes.flushPendingSave()
            if outcome.allowsTransition, let sender {
                self.allowsPendingClose = true
                sender.performClose(nil)
            }
            self.pendingCloseTask = nil
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        appModel.updatePresentationDemand(for: demandSource, isVisible: false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        appModel.updatePresentationDemand(for: demandSource, isVisible: false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        appModel.updatePresentationDemand(for: demandSource, isVisible: true)
    }

    private func showWindow() {
        let window = ensureWindow()
        appModel.clipboard.capturePasteTargetApplication()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        appModel.updatePresentationDemand(for: demandSource, isVisible: true)
    }

    private func ensureWindow() -> NSWindow {
        if let applicationWindow { return applicationWindow }

        let window = makeWindow()
        window.title = "CoreDeck"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(
            width: AppDesign.panelMinimumWidth,
            height: AppDesign.panelMinimumHeight
        )
        window.contentViewController = makeContentViewController(appModel)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.delegate = self
        applicationWindow = window
        return window
    }
}
