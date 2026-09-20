import Darwin
import Foundation

@main
struct MovementJournalTests {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--abandon-lock" {
            let lock = try MovementJournalLock(lockURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            withExtendedLifetime(lock) { _exit(0) }
        }
        let wifi = "com.apple.menuextra.wifi"
        let sound = "com.apple.menuextra.sound"
        let battery = "com.apple.menuextra.battery"
        let before = [item(wifi, 0, 20), item(sound, 20, 30), item(battery, 50, 20)]
        let moved = [item(sound, 0, 30), item(wifi, 30, 20), item(battery, 50, 20)]
        let base = Journal(
            schemaVersion: 1, createdAt: Date(), operatingSystem: "fixture-os",
            targetIdentifier: wifi, neighborIdentifier: sound, phase: .prepared,
            before: before, moved: nil, restored: nil, failure: nil
        )
        var assertions = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw TestFailure(label: label) }
            assertions += 1
        }
        func rejects(_ label: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch is Journal.ValidationError { assertions += 1; return }
            throw TestFailure(label: label)
        }
        func action(_ journal: Journal, _ current: [ItemSnapshot]) throws -> Journal.RecoveryAction {
            try journal.recoveryAction(for: current, operatingSystem: "fixture-os")
        }
        func alreadyRestored(_ action: Journal.RecoveryAction) -> Bool {
            if case .alreadyRestored = action { return true }
            return false
        }
        try check(alreadyRestored(try action(base, before)), "crash before input is already restored")
        if case let .swap(target, neighbor) = try action(base, moved) {
            try check(target.identifier == wifi && target.x == 30 && neighbor.identifier == sound,
                      "prepared crash uses current stable identities and geometry")
        } else { throw TestFailure(label: "prepared crash after drag must be recoverable") }
        try check(try base.verifiesMovement(moved), "unequal icon widths preserve the exact swap")
        try check(!(try base.verifiesMovement(before)), "unchanged order cannot report a move")
        try check(try base.verifiesRestoration(before), "restoration validates complete layout")
        var verified = base
        verified.phase = .moved
        verified.moved = moved
        if case .swap = try action(verified, moved) { assertions += 1 }
        else { throw TestFailure(label: "verified movement must recover") }
        verified.phase = .restoreFailed
        if case .swap = try action(verified, moved) { assertions += 1 }
        else { throw TestFailure(label: "explicit retry must recover an unchanged pending layout") }
        verified.phase = .restored
        try check(alreadyRestored(try action(verified, before)), "recovery is idempotent")
        try rejects("completed journal must not undo later user movement") { _ = try action(verified, moved) }
        try rejects("same order on another display must not count as restored") {
            _ = try action(base, before.map { item($0.identifier, $0.x + 200, $0.width) })
        }
        try rejects("conflicting manager order") {
            _ = try action(base, [item(battery, 0, 20), item(sound, 20, 30), item(wifi, 50, 20)])
        }
        try rejects("duplicate identity") { _ = try action(base, [before[0], before[0]]) }
        try rejects("missing neighbor") { _ = try action(base, [before[0], before[2]]) }
        try rejects("new item during recovery") { _ = try action(base, before + [item("new", 70, 20)]) }
        try rejects("non-finite coordinates") { _ = try action(base, [item(wifi, .infinity, 20)]) }
        try rejects("invalid size") { _ = try action(base, [item(wifi, 0, 0)]) }
        try rejects("empty snapshot") { _ = try action(base, []) }
        try rejects("unsorted snapshot") { _ = try action(base, Array(before.reversed())) }
        try rejects("different operating system") {
            _ = try base.recoveryAction(for: before, operatingSystem: "other-os")
        }
        var noObservation = base
        noObservation.phase = .moved
        try rejects("missing movement evidence") { _ = try action(noObservation, moved) }
        var corruptObservation = base
        corruptObservation.moved = before
        try rejects("incorrect movement evidence") { _ = try action(corruptObservation, moved) }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(base)
        try check(alreadyRestored(try action(decoder.decode(Journal.self, from: encoded), before)),
                  "persisted journal round trip")
        guard let originalObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw TestFailure(label: "journal fixture must be an object")
        }
        for (key, value) in [("schemaVersion", 2 as Any), ("targetIdentifier", "unknown" as Any),
                             ("neighborIdentifier", "com.apple.menuextra.clock" as Any),
                             ("neighborIdentifier", wifi as Any), ("neighborIdentifier", battery as Any)] {
            var object = originalObject
            object[key] = value
            let invalid = try decoder.decode(Journal.self, from: JSONSerialization.data(withJSONObject: object))
            try rejects("untrusted journal field: \(key)=\(value)") { _ = try action(invalid, moved) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("movement.lock")
        let first = try MovementJournalLock(lockURL: lockURL)
        do {
            let second = try MovementJournalLock(lockURL: lockURL)
            second.release()
            throw TestFailure(label: "concurrent movement was allowed")
        } catch is MovementJournalLock.LockError { assertions += 1 }
        first.release()
        let next = try MovementJournalLock(lockURL: lockURL)
        next.release()
        assertions += 1
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--abandon-lock", lockURL.path]
        try child.run()
        child.waitUntilExit()
        try check(child.terminationStatus == 0, "child acquired lock before abrupt exit")
        let afterCrash = try MovementJournalLock(lockURL: lockURL)
        afterCrash.release()
        assertions += 1
        let symlink = directory.appendingPathComponent("symlink.lock")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: lockURL)
        do {
            let unsafe = try MovementJournalLock(lockURL: symlink)
            unsafe.release()
            throw TestFailure(label: "symlink lock was allowed")
        } catch is MovementJournalLock.LockError { assertions += 1 }
        let journalURL = directory.appendingPathComponent("journal.json")
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(base).write(to: journalURL, options: .atomic)
        try check(alreadyRestored(try action(Journal.load(from: journalURL), before)),
                  "bounded journal load from disk")
        let journalLink = directory.appendingPathComponent("journal-link.json")
        try FileManager.default.createSymbolicLink(at: journalLink, withDestinationURL: journalURL)
        try rejects("journal symlink") { _ = try Journal.load(from: journalLink) }
        try rejects("journal directory") { _ = try Journal.load(from: directory) }
        try Data(repeating: 0, count: 1_048_577).write(to: journalURL)
        try rejects("oversized journal") { _ = try Journal.load(from: journalURL) }
        try Data().write(to: journalURL)
        try rejects("empty journal") { _ = try Journal.load(from: journalURL) }
        try Data("{broken".utf8).write(to: journalURL)
        do {
            _ = try Journal.load(from: journalURL)
            throw TestFailure(label: "corrupt journal was accepted")
        } catch is DecodingError { assertions += 1 }
        print("movement journal: \(assertions) assertions passed; no Accessibility or input events used")
    }

    private static func item(_ id: String, _ x: CGFloat, _ width: CGFloat) -> ItemSnapshot {
        ItemSnapshot(identifier: id, x: x, y: 0, width: width, height: 24)
    }

    private struct TestFailure: Error { let label: String }
}
