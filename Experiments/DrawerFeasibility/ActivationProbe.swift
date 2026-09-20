import AppKit
import ApplicationServices
import Foundation

// Interactive feasibility probe. It opens one native system-item menu and
// immediately dismisses it. It never changes placement or persistent settings.
@main
struct DrawerActivationProbe {
    private static let requiredIdentifiers = [
        "com.apple.menuextra.wifi",
        "com.apple.menuextra.bluetooth",
        "com.apple.menuextra.battery",
        "com.apple.menuextra.sound",
        "com.apple.menuextra.focusmode"
    ]

    static func main() {
        guard AXIsProcessTrusted() else {
            print("activation=blocked reason=accessibility-not-authorized")
            exit(2)
        }
        guard CommandLine.arguments.count == 2 else {
            print("usage: drawer-activation-probe <stable-identifier|all>")
            exit(64)
        }
        let requested = CommandLine.arguments[1]
        let identifiers = requested == "all" ? requiredIdentifiers : [requested]
        guard identifiers.allSatisfy(requiredIdentifiers.contains) else {
            print("activation=blocked reason=unsupported-identifier")
            exit(64)
        }

        let elements = discoverRequiredItems()
        var failed = false
        for identifier in identifiers {
            guard let element = elements[identifier] else {
                print("identifier=\(identifier) activation=failed reason=not-discovered")
                failed = true
                continue
            }
            let before = systemMenuWindows()
            let visibleMenusBefore = visibleSystemMenuCount()
            let status = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
            Thread.sleep(forTimeInterval: 0.35)
            let after = systemMenuWindows()
            let opened = after.subtracting(before)
            let visibleMenusAfter = visibleSystemMenuCount()
            print(
                "identifier=\(identifier) action=AXShowMenu status=\(status.rawValue) "
                    + "openedWindows=\(opened.map(\.description).sorted().joined(separator: ",")) "
                    + "visibleMenusBefore=\(visibleMenusBefore) "
                    + "visibleMenusAfter=\(visibleMenusAfter)"
            )
            dismissMenu()
            Thread.sleep(forTimeInterval: 0.35)
            let remaining = systemMenuWindows().intersection(opened)
            if !remaining.isEmpty {
                print(
                    "identifier=\(identifier) dismissal=failed remainingWindows="
                        + remaining.map(\.description).sorted().joined(separator: ",")
                )
            }
            let verifiedOpen = !opened.isEmpty || visibleMenusAfter > visibleMenusBefore
            let actionAccepted = status == .success || (status == .cannotComplete && verifiedOpen)
            if !actionAccepted || !verifiedOpen || !remaining.isEmpty {
                failed = true
            }
        }
        exit(failed ? 1 : 0)
    }

    private static func discoverRequiredItems() -> [String: AXUIElement] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.executableURL?.lastPathComponent == "MenuBarAgent"
        }) else { return [:] }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawMenuBar = value(application, "AXExtrasMenuBar"),
              CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else { return [:] }
        let menuBar = unsafeDowncast(rawMenuBar, to: AXUIElement.self)
        var result: [String: AXUIElement] = [:]
        collect(menuBar, depth: 0, into: &result)
        return result
    }

    private static func collect(
        _ element: AXUIElement,
        depth: Int,
        into result: inout [String: AXUIElement]
    ) {
        guard depth <= 5 else { return }
        if let identifier = value(element, kAXIdentifierAttribute) as? String,
           requiredIdentifiers.contains(identifier) {
            result[identifier] = element
        }
        guard let rawChildren = value(element, kAXChildrenAttribute),
              let children = rawChildren as? [AXUIElement] else { return }
        for child in children.prefix(100) {
            collect(child, depth: depth + 1, into: &result)
        }
    }

    private static func systemMenuWindows() -> Set<SystemMenuWindow> {
        let processIDs = Set(systemProcessApplications().map(\.processIdentifier))
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return Set(raw.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  processIDs.contains(pid),
                  let number = info[kCGWindowNumber as String] as? Int,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int
            else { return nil }
            return SystemMenuWindow(number: number, owner: owner, layer: layer)
        })
    }

    private static func visibleSystemMenuCount() -> Int {
        systemProcessApplications().reduce(into: 0) { count, app in
            count += visibleMenuCount(
                in: AXUIElementCreateApplication(app.processIdentifier),
                depth: 0
            )
        }
    }

    private static func visibleMenuCount(in element: AXUIElement, depth: Int) -> Int {
        guard depth <= 8 else { return 0 }
        let isVisibleMenu = value(element, kAXRoleAttribute) as? String == kAXMenuRole as String
            && value(element, "AXVisible") as? Bool == true
        var result = isVisibleMenu ? 1 : 0
        guard let rawChildren = value(element, kAXChildrenAttribute),
              let children = rawChildren as? [AXUIElement] else { return result }
        for child in children.prefix(200) {
            result += visibleMenuCount(in: child, depth: depth + 1)
        }
        return result
    }

    private static func systemProcessApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let executable = app.executableURL?.lastPathComponent else { return false }
            return ["ControlCenter", "SystemUIServer", "MenuBarAgent"].contains(executable)
        }
    }

    private struct SystemMenuWindow: Hashable {
        let number: Int
        let owner: String
        let layer: Int

        var description: String {
            "\(owner):\(number):layer\(layer)"
        }
    }

    private static func dismissMenu() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }
}
