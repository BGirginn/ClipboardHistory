import AppKit

@main
@MainActor
enum ClipboardHistoryLoginItemMain {
    static func main() {
        if NativeMessagingHost.shouldRun(arguments: ProcessInfo.processInfo.arguments) {
            NativeMessagingHost.run()
            return
        }
        let application = NSApplication.shared
        let delegate = LoginItemDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class LoginItemDelegate: NSObject, NSApplicationDelegate {
    private static let mainBundleIdentifier = "com.brgirgin.ClipboardHistory"

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mainBundleIdentifier
        ).isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let mainApplicationURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--background-launch"]
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: mainApplicationURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
