import Foundation
import SQLite3

extension StorageService {
    func rotateEncryptionKeyAfterCompleteErasure() throws {
        if let keyProvider {
            _ = try keyProvider.loadOrCreateKey()
            let keyData = try KeychainService.generateRandomKey()
            try keyProvider.replaceKey(with: keyData)
            encryption = try EncryptionService(keyData: keyData)
        } else {
            encryption = .ephemeral()
        }
        AppLog.storage.notice("Encryption key rotated after complete history erasure")
    }

    func encryptionService() throws -> EncryptionService {
        if let encryption { return encryption }
        guard let keyProvider else { throw DatabaseError.encryptionUnavailable }
        let liveEncryption = try EncryptionService(keyData: keyProvider.loadOrCreateKey())
        encryption = liveEncryption
        return liveEncryption
    }

    func deleteLogicalFile(_ filename: String, from directory: URL) {
        guard let filename = ManagedFilename(filename) else { return }
        for encrypted in [false, true] {
            let url = physicalURL(filename: filename.value, directory: directory, encrypted: encrypted)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    func associatedFileSize(for item: ClipboardItem) -> Int64 {
        var total: Int64 = 0
        var imageNames = item.assetFilenames
        if let imageFilename = item.imageFilename { imageNames.append(imageFilename) }
        for filename in imageNames {
            total += logicalFileSize(filename, directory: imagesDirectory)
        }
        if let filename = item.thumbnailFilename {
            total += logicalFileSize(filename, directory: thumbnailsDirectory)
        }
        if let filename = item.payloadFilename {
            total += logicalFileSize(filename, directory: payloadsDirectory)
        }
        return total
    }

    func logicalFileSize(_ filename: String, directory: URL) -> Int64 {
        guard let filename = ManagedFilename(filename) else { return 0 }
        return max(
            fileSize(at: physicalURL(filename: filename.value, directory: directory, encrypted: false)),
            fileSize(at: physicalURL(filename: filename.value, directory: directory, encrypted: true))
        )
    }

    func cleanupOrphanedFiles(referencedBy items: [ClipboardItem]) throws {
        var imageNames = Set(items.flatMap(\.assetFilenames))
        imageNames.formUnion(items.compactMap(\.imageFilename))
        let thumbnailNames = Set(items.compactMap(\.thumbnailFilename))
        let payloadNames = Set(items.compactMap(\.payloadFilename))
        try removeOrphans(in: imagesDirectory, logicalNames: imageNames)
        try removeOrphans(in: thumbnailsDirectory, logicalNames: thumbnailNames)
        try removeOrphans(in: payloadsDirectory, logicalNames: payloadNames)
    }

    func removeOrphans(in directory: URL, logicalNames: Set<String>) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let logicalName = url.lastPathComponent.hasSuffix(".enc")
                ? String(url.lastPathComponent.dropLast(4))
                : url.lastPathComponent
            if !logicalNames.contains(logicalName) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    func createDirectoriesIfNeeded() throws {
        for directory in [
            imagesDirectory, thumbnailsDirectory, payloadsDirectory,
            backupsDirectory, stagingDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func cleanupAbandonedStagingFiles() throws {
        let files = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    func recreateDirectory(_ directory: URL) throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(at: file)
        }
        return total
    }

    func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

}
