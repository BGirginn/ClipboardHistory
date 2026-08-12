import Foundation

extension StorageService {
    func clearAll() throws -> StorageMutationOutcome {
        try ensureInitialized()
        let quarantine = operationsDirectory.appending(
            path: "clear-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let operationID = quarantine.lastPathComponent
        let manifest = ClearOperationManifest(id: operationID)
        try JSONEncoder().encode(manifest).write(
            to: quarantine.appending(path: "manifest.json"),
            options: .atomic
        )
        let protectedDirectories = [
            imagesDirectory, thumbnailsDirectory, payloadsDirectory,
            backupsDirectory, stagingDirectory
        ]
        var movedDirectories: [(source: URL, quarantined: URL)] = []

        do {
            for source in protectedDirectories where fileManager.fileExists(atPath: source.path) {
                let quarantined = quarantine.appending(
                    path: source.lastPathComponent,
                    directoryHint: .isDirectory
                )
                try fileManager.moveItem(at: source, to: quarantined)
                movedDirectories.append((source, quarantined))
                try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
            }

            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM ClipboardItems")
                try execute("DELETE FROM ClipboardCollections")
                try setSettingValue(operationID, for: "lastCommittedClearOperation")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch {
            for move in movedDirectories.reversed() {
                if fileManager.fileExists(atPath: move.source.path) {
                    try? fileManager.removeItem(at: move.source)
                }
                if fileManager.fileExists(atPath: move.quarantined.path) {
                    try? fileManager.moveItem(at: move.quarantined, to: move.source)
                }
            }
            try? fileManager.removeItem(at: quarantine)
            throw error
        }

        var cleanupFailures: [String] = []
        do {
            try operationFailureInjector?(.removeAsset(quarantine.lastPathComponent))
            try fileManager.removeItem(at: quarantine)
            try deleteSettingValue(for: "lastCommittedClearOperation")
        } catch {
            cleanupFailures.append("quarantine-cleanup")
            AppLog.storage.error(
                "History rows were cleared but quarantine cleanup failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
        do {
            try removeQuickLookDerivatives()
        } catch {
            cleanupFailures.append("quick-look-cleanup")
            AppLog.storage.error(
                "History rows were cleared but Quick Look cleanup failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
        return StorageMutationOutcome(
            persistentChangeCommitted: true,
            cleanupFailures: cleanupFailures
        )
    }

    private func removeQuickLookDerivatives() throws {
        let temporaryRoot = fileManager.temporaryDirectory
        let contents = try fileManager.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent.hasPrefix("ClipboardHistoryPreview-") {
            try fileManager.removeItem(at: url)
        }
    }
}
