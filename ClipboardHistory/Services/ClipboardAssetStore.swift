import Foundation
import SQLite3

extension StorageService {
    func storeFile(
        data: Data,
        logicalFilename: String,
        directory: URL,
        encrypt: Bool
    ) -> Bool {
        do {
            try operationFailureInjector?(.storeAsset(logicalFilename))
            guard let logicalFilename = ManagedFilename(logicalFilename) else {
                throw DatabaseError.unsafeFilename
            }
            try createDirectoriesIfNeeded()
            let storedData: Data
            if encrypt {
                storedData = try encryptionService().encrypt(data)
            } else {
                storedData = data
            }
            let destination = physicalURL(
                filename: logicalFilename.value,
                directory: directory,
                encrypted: encrypt
            )
            let staged = stagingDirectory.appending(
                path: "\(UUID().uuidString.lowercased()).tmp",
                directoryHint: .notDirectory
            )
            try storedData.write(to: staged, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
            return true
        } catch {
            AppLog.storage.error(
                "Asset store failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    func loadFile(filename: String, directory: URL, isEncrypted: Bool) -> Data? {
        guard let filename = ManagedFilename(filename) else { return nil }
        let primary = physicalURL(filename: filename.value, directory: directory, encrypted: isEncrypted)
        let source = primary
        do {
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            if isEncrypted {
                return try encryptionService().decrypt(data)
            }
            return data
        } catch {
            AppLog.storage.error(
                "Asset read failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    nonisolated func physicalURL(filename: String, directory: URL, encrypted: Bool) -> URL {
        directory.appending(
            path: encrypted ? "\(filename).enc" : filename,
            directoryHint: .notDirectory
        )
    }

    func deleteAssociatedFiles(for item: ClipboardItem) {
        var imageNames = item.assetFilenames
        if let imageFilename = item.imageFilename {
            imageNames.append(imageFilename)
        }
        for filename in imageNames {
            deleteLogicalFile(filename, from: imagesDirectory)
        }
        if let thumbnailFilename = item.thumbnailFilename {
            deleteLogicalFile(thumbnailFilename, from: thumbnailsDirectory)
        }
        if let payloadFilename = item.payloadFilename {
            deleteLogicalFile(payloadFilename, from: payloadsDirectory)
        }
    }

    func rewriteAssets(for item: ClipboardItem, encrypt: Bool) throws -> Bool {
        var imageNames = item.assetFilenames
        if let filename = item.imageFilename { imageNames.append(filename) }
        for filename in imageNames {
            guard let data = loadFile(
                filename: filename,
                directory: imagesDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: imagesDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        if let filename = item.thumbnailFilename,
           fileExists(logicalFilename: filename, directory: thumbnailsDirectory, encrypted: item.isEncrypted) {
            guard let data = loadFile(
                filename: filename,
                directory: thumbnailsDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: thumbnailsDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        if let filename = item.payloadFilename {
            guard let data = loadFile(
                filename: filename,
                directory: payloadsDirectory,
                isEncrypted: item.isEncrypted
            ), storeFile(
                data: data,
                logicalFilename: filename,
                directory: payloadsDirectory,
                encrypt: encrypt
            ) else { return false }
        }
        return true
    }

    func deletePhysicalAssets(for item: ClipboardItem, encrypted: Bool) {
        var imageNames = item.assetFilenames
        if let filename = item.imageFilename { imageNames.append(filename) }
        for filename in imageNames {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: imagesDirectory, encrypted: encrypted)
            )
        }
        if let filename = item.thumbnailFilename {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: thumbnailsDirectory, encrypted: encrypted)
            )
        }
        if let filename = item.payloadFilename {
            try? fileManager.removeItem(
                at: physicalURL(filename: filename, directory: payloadsDirectory, encrypted: encrypted)
            )
        }
    }

    func fileExists(logicalFilename: String, directory: URL, encrypted: Bool) -> Bool {
        guard let logicalFilename = ManagedFilename(logicalFilename) else { return false }
        return fileManager.fileExists(
            atPath: physicalURL(
                filename: logicalFilename.value,
                directory: directory,
                encrypted: encrypted
            ).path
        )
    }

}
