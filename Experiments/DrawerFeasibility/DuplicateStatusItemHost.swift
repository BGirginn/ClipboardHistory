import AppKit

@MainActor
private final class DuplicateStatusItemDelegate: NSObject, NSApplicationDelegate {
    private var statusItems: [NSStatusItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItems = [
            makeStatusItem(identifier: "com.coredeck.drawer-fixture.primary"),
            makeStatusItem(identifier: "com.coredeck.drawer-fixture.secondary")
        ]
        print("fixture=ready count=\(statusItems.count)")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            NSApp.terminate(nil)
        }
    }

    private func makeStatusItem(identifier: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = identifier
        if let button = item.button {
            button.title = "Fixture"
            button.setAccessibilityIdentifier(identifier)
            button.setAccessibilityLabel("Drawer duplicate identity fixture")
        }
        return item
    }
}

@main
@MainActor
private struct DuplicateStatusItemHost {
    static func main() {
        let application = NSApplication.shared
        let delegate = DuplicateStatusItemDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
