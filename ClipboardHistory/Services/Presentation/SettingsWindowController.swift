import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, SettingsWindowPresenting, NSWindowDelegate {
    private static let frameAutosaveName = "ClipboardHistory.SettingsWindow"

    private let appModel: AppModel
    private let makeWindow: () -> NSWindow
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
        }
    ) {
        self.appModel = appModel
        self.makeWindow = makeWindow
        super.init()
    }

    func show(section: AppSettingsSection?) {
        let requested = section?.defaultSubsection ?? selectedSubsection
        if let requested { selectedSubsection = requested }
        let window = ensureWindow()
        window.contentViewController = makeContentViewController(initialSubsection: requested)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
        window.contentMinSize = NSSize(width: 680, height: 500)
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.delegate = self
        settingsWindow = window
        return window
    }

    private func makeContentViewController(
        initialSubsection: AppSettingsSubsection?
    ) -> NSViewController {
        NSHostingController(
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
    }
}
