import Darwin
import Foundation

struct ItemSnapshot: Codable, Equatable {
    let identifier: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var center: CGPoint {
        CGPoint(x: x + (width / 2), y: y + (height / 2))
    }
}

struct Journal: Codable {
    static let supportedIdentifiers = Set([
        "com.apple.menuextra.wifi", "com.apple.menuextra.bluetooth",
        "com.apple.menuextra.battery", "com.apple.menuextra.sound",
        "com.apple.menuextra.focusmode"
    ])

    let schemaVersion: Int
    let createdAt: Date
    let operatingSystem: String
    let targetIdentifier: String
    let neighborIdentifier: String
    var phase: Phase
    let before: [ItemSnapshot]
    var moved: [ItemSnapshot]?
    var restored: [ItemSnapshot]?
    var failure: String?

    enum Phase: String, Codable {
        case prepared
        case moved
        case moveFailed
        case restored
        case restoreFailed
    }

    enum RecoveryAction {
        case alreadyRestored
        case swap(target: ItemSnapshot, neighbor: ItemSnapshot)
    }

    struct ValidationError: LocalizedError {
        let reason: String
        var errorDescription: String? { "Recovery stopped without input: \(reason)" }
    }

    static func load(from url: URL) throws -> Journal {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ValidationError(reason: "journal cannot be opened safely") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { handle.closeFile() }
        var status = stat()
        let limit = 1_048_576
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size > 0, status.st_size <= limit,
              let data = try handle.read(upToCount: limit + 1), data.count <= limit else {
            throw ValidationError(reason: "journal is not a bounded regular file")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Journal.self, from: data)
    }

    func recoveryAction(
        for current: [ItemSnapshot],
        operatingSystem currentOperatingSystem: String
    ) throws -> RecoveryAction {
        guard schemaVersion == 1, operatingSystem == currentOperatingSystem else {
            throw ValidationError(reason: "journal schema or operating system differs")
        }
        guard Self.supportedIdentifiers.contains(targetIdentifier),
              Self.supportedIdentifiers.contains(neighborIdentifier),
              targetIdentifier != neighborIdentifier else {
            throw ValidationError(reason: "target or neighbor is not an allowed stable identity")
        }
        try Self.validateSnapshot(before)
        try Self.validateSnapshot(current)
        let swapped = try swappedLayout()
        if let moved {
            try Self.validateSnapshot(moved)
            guard Self.matches(moved, swapped) else {
                throw ValidationError(reason: "recorded movement is not the intended adjacent swap")
            }
        } else if phase == .moved {
            throw ValidationError(reason: "verified movement has no observation")
        }
        if Self.matches(current, before) { return .alreadyRestored }
        guard phase != .restored, Self.matches(current, swapped),
              let target = current.first(where: { $0.identifier == targetIdentifier }),
              let neighbor = current.first(where: { $0.identifier == neighborIdentifier }) else {
            throw ValidationError(reason: "current identities, geometry or order conflict with the journal")
        }
        // A crash may leave `prepared` on disk even though the drag reached macOS.
        // Only the exact intended swap is safe to reverse in that state.
        return .swap(target: target, neighbor: neighbor)
    }

    func verifiesMovement(_ observed: [ItemSnapshot]) throws -> Bool {
        try Self.validateSnapshot(before)
        try Self.validateSnapshot(observed)
        return Self.matches(observed, try swappedLayout())
    }

    func verifiesRestoration(_ observed: [ItemSnapshot]) throws -> Bool {
        try Self.validateSnapshot(observed)
        return Self.matches(observed, before)
    }

    private func swappedLayout() throws -> [ItemSnapshot] {
        guard let target = before.firstIndex(where: { $0.identifier == targetIdentifier }),
              let neighbor = before.firstIndex(where: { $0.identifier == neighborIdentifier }),
              abs(target - neighbor) == 1 else {
            throw ValidationError(reason: "original target and neighbor are missing or not adjacent")
        }
        let leftIndex = min(target, neighbor)
        let rightIndex = max(target, neighbor)
        let left = before[leftIndex]
        let right = before[rightIndex]
        var result = before
        result[leftIndex] = ItemSnapshot(
            identifier: right.identifier, x: left.x, y: right.y,
            width: right.width, height: right.height
        )
        result[rightIndex] = ItemSnapshot(
            identifier: left.identifier, x: right.x + right.width - left.width, y: left.y,
            width: left.width, height: left.height
        )
        return result
    }

    private static func validateSnapshot(_ items: [ItemSnapshot]) throws {
        guard !items.isEmpty, items.count <= 100,
              Set(items.map(\.identifier)).count == items.count,
              items.allSatisfy({
                  !$0.identifier.isEmpty && $0.x.isFinite && $0.y.isFinite
                      && $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
                      && $0.center.x.isFinite && $0.center.y.isFinite
              }), zip(items, items.dropFirst()).allSatisfy({ $0.x < $1.x }) else {
            throw ValidationError(reason: "snapshot is empty, ambiguous, unordered or has invalid geometry")
        }
    }

    private static func matches(_ observed: [ItemSnapshot], _ expected: [ItemSnapshot]) -> Bool {
        observed.count == expected.count && zip(observed, expected).allSatisfy { lhs, rhs in
            lhs.identifier == rhs.identifier && abs(lhs.x - rhs.x) <= 2
                && abs(lhs.y - rhs.y) <= 2 && abs(lhs.width - rhs.width) <= 2
                && abs(lhs.height - rhs.height) <= 2
        }
    }
}
