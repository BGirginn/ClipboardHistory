import AppKit

@main
@MainActor
enum CoreDeckMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = CoreDeckAppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
