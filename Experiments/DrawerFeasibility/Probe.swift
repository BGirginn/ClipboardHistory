import AppKit
import ApplicationServices
import Foundation

// Read-only discovery probe. It never changes a status item or grants permission.
@main
struct DrawerFeasibilityProbe {
    static func main() {
        guard AXIsProcessTrusted() else {
            print("accessibility=not-authorized")
            return
        }
        for executableName in ["ControlCenter", "SystemUIServer", "MenuBarAgent"] {
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.executableURL?.lastPathComponent == executableName
            }
            print("process=\(executableName) count=\(apps.count)")
            for app in apps {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                if let menuBar = value(application, "AXExtrasMenuBar"),
                   CFGetTypeID(menuBar) == AXUIElementGetTypeID() {
                    // The CF type ID check precedes this Swift bridge.
                    inspect(unsafeDowncast(menuBar, to: AXUIElement.self), depth: 0)
                } else {
                    print("menuBar=unavailable")
                    var ignored: CFTypeRef?
                    let status = AXUIElementCopyAttributeValue(
                        application, "AXExtrasMenuBar" as CFString, &ignored
                    )
                    print("extrasMenuBarReadStatus=\(status.rawValue)")
                    var attributes: CFArray?
                    if AXUIElementCopyAttributeNames(application, &attributes) == .success,
                       let names = attributes as? [String] {
                        print("applicationAttributes=\(names.sorted().joined(separator: ","))")
                    }
                }
            }
        }
    }

    private static func inspect(_ element: AXUIElement, depth: Int) {
        guard depth <= 5 else { return }
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        let requiredItems = [
            ("Wi-Fi", "com.apple.menuextra.wifi"),
            ("Bluetooth", "com.apple.menuextra.bluetooth"),
            ("Battery", "com.apple.menuextra.battery"),
            ("Sound", "com.apple.menuextra.sound"),
            ("Focus", "com.apple.menuextra.focusmode")
        ]
        let target = requiredItems.first { $0.1 == identifier }?.0
        if let target {
            let role = string(element, kAXRoleAttribute) ?? "<none>"
            let position = point(element, kAXPositionAttribute)
            let size = size(element, kAXSizeAttribute)
            let actions = actionNames(element).joined(separator: ",")
            let actionDescription = actions.isEmpty ? "<none>" : actions
            print(
                "target=\(target) role=\(role) identifier=\(identifier) "
                    + "position=\(formatted(position)) size=\(formatted(size)) "
                    + "positionSettable=\(isSettable(element, kAXPositionAttribute)) "
                    + "actions=\(actionDescription)"
            )
        } else if identifier.hasPrefix("com.apple.menuextra.") {
            print("otherSystemIdentifier=\(identifier)")
        }
        guard let raw = value(element, kAXChildrenAttribute),
              let children = raw as? [AXUIElement] else { return }
        for child in children.prefix(100) {
            inspect(child, depth: depth + 1)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String] ?? []).sorted()
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var result = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &result
        ) == .success else { return false }
        return result.boolValue
    }

    private static func formatted(_ point: CGPoint?) -> String {
        guard let point else { return "<unavailable>" }
        return "\(Int(point.x)),\(Int(point.y))"
    }

    private static func formatted(_ size: CGSize?) -> String {
        guard let size else { return "<unavailable>" }
        return "\(Int(size.width))x\(Int(size.height))"
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }
}
