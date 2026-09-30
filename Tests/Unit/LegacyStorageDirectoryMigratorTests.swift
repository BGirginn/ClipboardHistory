import Foundation
import XCTest

@testable import CoreDeckTestHost

final class LegacyStorageDirectoryMigratorTests: XCTestCase {
    func testCopiesLegacyDirectoryAndPreservesSource() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let sourceFile = context.legacy.appending(path: "history.sqlite3")
        let contents = Data("existing history".utf8)
        try contents.write(to: sourceFile)

        try LegacyStorageDirectoryMigrator(isLegacyApplicationRunning: { false })
            .migrateIfNeeded(from: context.legacy, to: context.destination)

        XCTAssertEqual(try Data(contentsOf: sourceFile), contents)
        XCTAssertEqual(
            try Data(contentsOf: context.destination.appending(path: "history.sqlite3")), contents
        )
        try LegacyStorageDirectoryMigrator(isLegacyApplicationRunning: { false })
            .migrateIfNeeded(from: context.legacy, to: context.destination)
    }

    func testRefusesConflictWithoutChangingEitherDirectory() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
        let existing = context.destination.appending(path: "history.sqlite3")
        try Data("new history".utf8).write(to: existing)

        XCTAssertThrowsError(
            try LegacyStorageDirectoryMigrator(isLegacyApplicationRunning: { false })
                .migrateIfNeeded(from: context.legacy, to: context.destination)
        ) { error in
            guard case DatabaseError.migrationConflict = error else {
                return XCTFail("Expected migrationConflict, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("new history".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.legacy.path))
    }

    func testRefusesMigrationWhilePreviousApplicationRuns() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        XCTAssertThrowsError(
            try LegacyStorageDirectoryMigrator(isLegacyApplicationRunning: { true })
                .migrateIfNeeded(from: context.legacy, to: context.destination)
        ) { error in
            guard case DatabaseError.legacyApplicationRunning = error else {
                return XCTFail("Expected legacyApplicationRunning, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.legacy.path))
    }

    func testFilesystemFailurePreservesLegacyData() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let blockedParent = context.root.appending(path: "blocked")
        try Data("not a directory".utf8).write(to: blockedParent)
        let destination = blockedParent.appending(path: "CoreDeck")

        XCTAssertThrowsError(
            try LegacyStorageDirectoryMigrator(isLegacyApplicationRunning: { false })
                .migrateIfNeeded(from: context.legacy, to: destination)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func makeContext() throws -> (root: URL, legacy: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CoreDeckMigration-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        let legacy = root.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        return (root, legacy, root.appending(path: "CoreDeck", directoryHint: .isDirectory))
    }
}
