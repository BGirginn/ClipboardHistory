import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, SettingsWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = "CoreDeck.SettingsWindow.v2"
    private static let idealContentSize = NSSize(width: 820, height: 620)
    private static let minimumContentSize = NSSize(width: 680, height: 500)

    private let appModel: AppModel
    private let makeWindow: () -> NSWindow
    private let configureFrameAutosave: (NSWindow) -> Void
    private let restoreFrame: (NSWindow) -> Bool
    private var settingsWindow: NSWindow?
    private var selectedSubsection: AppSettingsSubsection?

    var isWindowVisible: Bool { settingsWindow?.isVisible == true }
    var presentedSubsection: AppSettingsSubsection? { selectedSubsection }

    init(
        appModel: AppModel,
        makeWindow: @escaping () -> NSWindow = {
            NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        },
        configureFrameAutosave: @escaping (NSWindow) -> Void = {
            $0.setFrameAutosaveName(SettingsWindowController.frameAutosaveName)
        },
        restoreFrame: @escaping (NSWindow) -> Bool = {
            $0.setFrameUsingName(SettingsWindowController.frameAutosaveName)
        }
    ) {
        self.appModel = appModel
        self.makeWindow = makeWindow
        self.configureFrameAutosave = configureFrameAutosave
        self.restoreFrame = restoreFrame
        super.init()
    }

    func show(section: AppSettingsSection?) {
        let requested = section?.defaultSubsection ?? selectedSubsection
        if let requested { selectedSubsection = requested }
        let window = ensureWindow()
        let preservedContentSize = window.contentView?.frame.size
            ?? window.contentLayoutRect.size
        let contentController = makeContentViewController(initialSubsection: requested)
        contentController.preferredContentSize = preservedContentSize
        window.contentViewController = contentController
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(preservedContentSize)
    }

    func close() {
        settingsWindow?.performClose(nil)
    }

    func stop() {
        settingsWindow?.delegate = nil
        settingsWindow?.close()
        settingsWindow = nil
    }

    private func ensureWindow() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        let window = makeWindow()
        window.title = String(localized: "CoreDeck Settings")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = Self.minimumContentSize
        configureFrameAutosave(window)
        let restoredFrame = restoreFrame(window)
        let restoredSize = window.contentLayoutRect.size
        let restoredFrameIsUsable = restoredFrame
            && restoredSize.width >= Self.minimumContentSize.width
            && restoredSize.height >= Self.minimumContentSize.height
        if !restoredFrameIsUsable {
            window.setContentSize(Self.idealContentSize)
            window.center()
        }
        window.delegate = self
        settingsWindow = window
        return window
    }

    private func makeContentViewController(
        initialSubsection: AppSettingsSubsection?
    ) -> NSViewController {
        let controller = NSHostingController(
            rootView: AppSettingsView(
                viewModel: appModel.settingsFeature,
                initialSection: initialSubsection?.section,
                initialSubsection: initialSubsection,
                close: { [weak self] in self?.close() },
                selectionChanged: { [weak self] subsection in
                    if let subsection { self?.selectedSubsection = subsection }
                }
            )
            .preferredColorScheme(appModel.settings.appearance.colorScheme)
        )
        controller.sizingOptions = []
        return controller
    }
}
