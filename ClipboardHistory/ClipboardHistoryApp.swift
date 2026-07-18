import AppKit
import Foundation

@main
@MainActor
enum ClipboardHistoryMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ClipboardHistoryAppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class ClipboardHistoryAppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: ClipboardHistoryViewModel?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            AppLog.lifecycle.debug("Application services disabled for hosted unit tests")
            return
        }
        let viewModel = ClipboardHistoryViewModel()
        self.viewModel = viewModel
        menuBarController = MenuBarController(viewModel: viewModel)
        AppLog.lifecycle.notice("Application launched; interface=menu-bar")
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.prepareForShutdown()
        menuBarController?.stop()
        menuBarController = nil
        viewModel = nil
    }
}
