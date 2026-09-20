import AppKit
import ApplicationServices
import Foundation

@main
struct DrawerMovementProbe {
    static func main() {
        do {
            try run()
        } catch {
            print("movement=failed error=\(error.localizedDescription)")
            exit(1)
        }
    }

    private static func run() throws {
        guard AXIsProcessTrusted() else { throw ProbeError.accessibilityNotAuthorized }
        guard [4, 5].contains(CommandLine.arguments.count),
              CommandLine.arguments[3] == "--confirm-system-menu-change"
        else { throw ProbeError.invalidArguments }

        let journalURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let journalLock = try MovementJournalLock()
        defer { journalLock.release() }

        if CommandLine.arguments[1] == "--recover" {
            guard CommandLine.arguments.count == 4 else { throw ProbeError.invalidArguments }
            try recover(
                journalURL: URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
            )
            return
        }

        let identifier = CommandLine.arguments[1]
        let leavesMovedForRestart = CommandLine.arguments.count == 5
            && CommandLine.arguments[4] == "--leave-moved-for-restart"
        guard CommandLine.arguments.count == 4 || leavesMovedForRestart else {
            throw ProbeError.invalidArguments
        }
        guard Journal.supportedIdentifiers.contains(identifier) else {
            throw ProbeError.unsupportedIdentifier(identifier)
        }
        guard !FileManager.default.fileExists(atPath: journalURL.path) else {
            throw ProbeError.journalAlreadyExists
        }
        let originalPointer = CGEvent(source: nil)?.location
        let pointerRestore = try originalPointer.map { try mouseEvent(type: .mouseMoved, at: $0, flags: []) }
        defer { pointerRestore?.post(tap: .cghidEventTap) }

        let before = try snapshot()
        guard let targetIndex = before.firstIndex(where: { $0.identifier == identifier }) else {
            throw ProbeError.itemNotDiscovered(identifier)
        }
        guard before.filter({ $0.identifier == identifier }).count == 1 else {
            throw ProbeError.duplicateIdentifier(identifier)
        }
        let neighborIndex = try movableNeighborIndex(for: targetIndex, in: before)
        let target = before[targetIndex]
        let neighbor = before[neighborIndex]

        var journal = Journal(
            schemaVersion: 1,
            createdAt: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            targetIdentifier: identifier,
            neighborIdentifier: neighbor.identifier,
            phase: .prepared,
            before: before,
            moved: nil,
            restored: nil,
            failure: nil
        )
        _ = try journal.recoveryAction(
            for: before, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
        try write(journal, to: journalURL)

        try commandDrag(from: target.center, to: movementDestination(target: target, neighbor: neighbor))
        Thread.sleep(forTimeInterval: 1)
        let moved = try snapshot()
        journal.moved = moved
        guard try journal.verifiesMovement(moved) else {
            journal.phase = .moveFailed
            journal.failure = "The observed layout did not match the intended adjacent swap; automatic recovery stopped."
            try write(journal, to: journalURL)
            throw ProbeError.moveNotObserved
        }
        journal.phase = .moved
        try write(journal, to: journalURL)
        if leavesMovedForRestart {
            print(
                "movement=pending-restart-recovery identifier=\(identifier) "
                    + "journal=\(journalURL.path)"
            )
            return
        }

        try recover(journalURL: journalURL)
        print(
            "movement=passed identifier=\(identifier) neighbor=\(neighbor.identifier) "
                + "journal=\(journalURL.path)"
        )
    }

    private static func recover(journalURL: URL) throws {
        var journal = try Journal.load(from: journalURL)
        let current = try snapshot()
        let action = try journal.recoveryAction(
            for: current, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
        let target: ItemSnapshot
        let neighbor: ItemSnapshot
        switch action {
        case .alreadyRestored:
            journal.restored = current
            journal.phase = .restored
            journal.failure = nil
            try write(journal, to: journalURL)
            print("recovery=already-restored journal=\(journalURL.path)")
            return
        case let .swap(observedTarget, observedNeighbor):
            target = observedTarget
            neighbor = observedNeighbor
        }
        try commandDrag(
            from: target.center,
            to: movementDestination(target: target, neighbor: neighbor)
        )
        Thread.sleep(forTimeInterval: 1)
        let restored = try snapshot()
        journal.restored = restored
        guard try journal.verifiesRestoration(restored) else {
            journal.phase = .restoreFailed
            journal.failure = "Recovery did not restore the original order and position."
            try write(journal, to: journalURL)
            throw ProbeError.restoreNotVerified
        }
        journal.phase = .restored
        journal.failure = nil
        try write(journal, to: journalURL)
        print("recovery=passed journal=\(journalURL.path)")
    }

    private static func movableNeighborIndex(
        for targetIndex: Int,
        in items: [ItemSnapshot]
    ) throws -> Int {
        let candidates = [targetIndex - 1, targetIndex + 1]
        for index in candidates where items.indices.contains(index) {
            let identifier = items[index].identifier
            if Journal.supportedIdentifiers.contains(identifier),
               items.filter({ $0.identifier == identifier }).count == 1 {
                return index
            }
        }
        throw ProbeError.noSafeNeighbor
    }

    private static func movementDestination(
        target: ItemSnapshot,
        neighbor: ItemSnapshot
    ) -> CGPoint {
        let movesLeft = neighbor.center.x < target.center.x
        let offset = max(2, target.width / 2)
        return CGPoint(
            x: neighbor.center.x + (movesLeft ? -offset : offset),
            y: target.center.y
        )
    }

    private static func commandDrag(from source: CGPoint, to destination: CGPoint) throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw ProbeError.inputMonitoringNotAuthorized
        }
        // Allocate every event, especially mouse-up, before holding any button down.
        let hover = try mouseEvent(type: .mouseMoved, at: source, flags: [])
        let down = try mouseEvent(type: .leftMouseDown, at: source, flags: .maskCommand)
        let up = try mouseEvent(type: .leftMouseUp, at: destination, flags: .maskCommand)
        let drag = try (1...12).map { step in
            let progress = CGFloat(step) / 12
            return try mouseEvent(
                type: .leftMouseDragged,
                at: CGPoint(
                    x: source.x + ((destination.x - source.x) * progress),
                    y: source.y + ((destination.y - source.y) * progress)
                ), flags: .maskCommand
            )
        }
        hover.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.15)
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw ProbeError.inputMonitoringNotAuthorized
        }
        down.post(tap: .cghidEventTap)
        defer { up.post(tap: .cghidEventTap) }
        Thread.sleep(forTimeInterval: 0.2)
        for event in drag {
            guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
                throw ProbeError.inputMonitoringNotAuthorized
            }
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.04)
        }
    }

    private static func mouseEvent(
        type: CGEventType, at point: CGPoint, flags: CGEventFlags
    ) throws -> CGEvent {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                  mouseEventSource: source, mouseType: type,
                  mouseCursorPosition: point, mouseButton: .left
              ) else { throw ProbeError.eventAllocationFailed }
        event.flags = flags
        return event
    }

    private static func snapshot() throws -> [ItemSnapshot] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.executableURL?.lastPathComponent == "MenuBarAgent"
        }) else { throw ProbeError.menuBarAgentUnavailable }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawMenuBar = value(application, "AXExtrasMenuBar"),
              CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else {
            throw ProbeError.extrasMenuBarUnavailable
        }
        let menuBar = unsafeDowncast(rawMenuBar, to: AXUIElement.self)
        var items: [ItemSnapshot] = []
        collect(menuBar, depth: 0, into: &items)
        return items.sorted { lhs, rhs in
            if lhs.center.x == rhs.center.x { return lhs.identifier < rhs.identifier }
            return lhs.center.x < rhs.center.x
        }
    }

    private static func collect(
        _ element: AXUIElement,
        depth: Int,
        into items: inout [ItemSnapshot]
    ) {
        guard depth <= 5 else { return }
        if let identifier = value(element, kAXIdentifierAttribute) as? String,
           !identifier.isEmpty,
           let position = point(element, kAXPositionAttribute),
           let size = size(element, kAXSizeAttribute),
           size.width > 0,
           size.height > 0 {
            items.append(
                ItemSnapshot(
                    identifier: identifier,
                    x: position.x,
                    y: position.y,
                    width: size.width,
                    height: size.height
                )
            )
        }
        guard let rawChildren = value(element, kAXChildrenAttribute),
              let children = rawChildren as? [AXUIElement] else { return }
        for child in children.prefix(100) {
            collect(child, depth: depth + 1, into: &items)
        }
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

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }

    private static func write(_ journal: Journal, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: url, options: [.atomic])
    }
}

private enum ProbeError: LocalizedError {
    case accessibilityNotAuthorized
    case inputMonitoringNotAuthorized
    case invalidArguments
    case unsupportedIdentifier(String)
    case menuBarAgentUnavailable
    case extrasMenuBarUnavailable
    case itemNotDiscovered(String)
    case duplicateIdentifier(String)
    case noSafeNeighbor
    case moveNotObserved
    case restoreNotVerified
    case journalAlreadyExists
    case eventAllocationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotAuthorized:
            "Accessibility permission is not available."
        case .inputMonitoringNotAuthorized:
            "Event posting permission is not available."
        case .invalidArguments:
            "Usage: movement-probe <stable-identifier> <journal-path> --confirm-system-menu-change [--leave-moved-for-restart], or movement-probe --recover <journal-path> --confirm-system-menu-change"
        case let .unsupportedIdentifier(identifier):
            "Unsupported identifier: \(identifier)"
        case .menuBarAgentUnavailable:
            "MenuBarAgent is not running."
        case .extrasMenuBarUnavailable:
            "AXExtrasMenuBar is unavailable."
        case let .itemNotDiscovered(identifier):
            "Item was not discovered: \(identifier)"
        case let .duplicateIdentifier(identifier):
            "Identifier is not unique: \(identifier)"
        case .noSafeNeighbor:
            "No safe adjacent item is available for the movement test."
        case .moveNotObserved:
            "Movement was not observed."
        case .restoreNotVerified:
            "Restore could not be verified; inspect the journal before retrying."
        case .journalAlreadyExists:
            "Journal already exists; recover it explicitly or choose a new path."
        case .eventAllocationFailed:
            "Could not allocate every input event; no drag was started."
        }
    }
}
