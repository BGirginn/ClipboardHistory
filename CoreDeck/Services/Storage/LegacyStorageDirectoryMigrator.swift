import AppKit
import Foundation

struct LegacyStorageDirectoryMigrator {
    private static let completionMarker = ".coredeck-migrated-from-clipboardhistory"
    private let fileManager: FileManager
    private let isLegacyApplicationRunning: () -> Bool

    init(
        fileManager: FileManager = .default,
        isLegacyApplicationRunning: @escaping () -> Bool = {
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.brgirgin.ClipboardHistory"
            ).isEmpty
        }
    ) {
        self.fileManager = fileManager
        self.isLegacyApplicationRunning = isLegacyApplicationRunning
    }

    func migrateIfNeeded(from legacyDirectory: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return }
        guard !isLegacyApplicationRunning() else {
            throw DatabaseError.legacyApplicationRunning
        }
        if fileManager.fileExists(atPath: destination.path) {
            let marker = destination.appending(path: Self.completionMarker)
            guard fileManager.fileExists(atPath: marker.path) else {
                throw DatabaseError.migrationConflict
            }
            return
        }

        let staging = destination.deletingLastPathComponent().appending(
            path: ".CoreDeck-migration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.copyItem(at: legacyDirectory, to: staging)
            try Data().write(to: staging.appending(path: Self.completionMarker))
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if fileManager.fileExists(atPath: staging.path) {
                do {
                    try fileManager.removeItem(at: staging)
                } catch {
                    throw DatabaseError.executionFailed(
                        "Incomplete data migration could not be cleaned up: \(error.localizedDescription)"
                    )
                }
            }
            throw error
        }
    }
}
