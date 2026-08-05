import AppKit

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
