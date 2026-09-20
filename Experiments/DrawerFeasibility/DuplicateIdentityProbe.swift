import AppKit
import ApplicationServices
import Foundation

@main
struct DuplicateIdentityProbe {
    private static let expected = Set([
        "com.coredeck.drawer-fixture.primary",
        "com.coredeck.drawer-fixture.secondary"
    ])

    static func main() {
        guard AXIsProcessTrusted() else {
            print("duplicateIdentity=blocked reason=accessibility-not-authorized")
            exit(2)
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.executableURL?.lastPathComponent == "coredeck-drawer-duplicate-host"
        }) else {
            print("duplicateIdentity=failed reason=fixture-not-running")
            exit(1)
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawMenuBar = value(application, "AXExtrasMenuBar"),
              CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else {
            print("duplicateIdentity=failed reason=extras-menu-bar-unavailable")
            exit(1)
        }
        let menuBar = unsafeDowncast(rawMenuBar, to: AXUIElement.self)
        var discovered: [(identifier: String, title: String)] = []
        collect(menuBar, depth: 0, into: &discovered)
        for item in discovered.sorted(by: { $0.identifier < $1.identifier }) {
            print("identifier=\(item.identifier) title=\(item.title)")
        }
        let identifiers = Set(discovered.map(\.identifier))
        guard identifiers == expected, discovered.count == expected.count else {
            print("duplicateIdentity=failed count=\(discovered.count)")
            exit(1)
        }
        print("duplicateIdentity=passed count=\(discovered.count)")
    }

    private static func collect(
        _ element: AXUIElement,
        depth: Int,
        into discovered: inout [(identifier: String, title: String)]
    ) {
        guard depth <= 5 else { return }
        if let identifier = value(element, kAXIdentifierAttribute) as? String,
           expected.contains(identifier) {
            let title = value(element, kAXTitleAttribute) as? String ?? "<none>"
            discovered.append((identifier, title))
        }
        guard let rawChildren = value(element, kAXChildrenAttribute),
              let children = rawChildren as? [AXUIElement] else { return }
        for child in children.prefix(100) {
            collect(child, depth: depth + 1, into: &discovered)
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }
}
