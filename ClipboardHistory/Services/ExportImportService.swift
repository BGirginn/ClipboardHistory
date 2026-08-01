import Foundation

actor ExportImportService {
    private let maximumArchiveBytes = 512_000_000
    private let maximumAssetBytes = 128_000_000
    private let maximumItemCount = 50_000

    func exportArchive(
        items: [ClipboardItem],
        storage: StorageService,
        to destination: URL,
        mode: ClipboardExportMode,
        includeImagesAndDocuments: Bool,
        includeFileReferences: Bool = true,
        collections: [ClipboardCollection] = [],
        password: String? = nil
    ) async throws {
        let eligible = items.filter { item in
            (!item.isSensitive || item.isEncrypted)
                && (includeFileReferences || item.type != .files)
        }
        let archiveItems: [ClipboardItem]
        var assets: [String: Data] = [:]

        if mode == .metadataOnly {
            archiveItems = eligible.map(metadataOnlyItem)
        } else {
            archiveItems = eligible.map { item in
                var copy = item
                copy.isEncrypted = false
                copy.thumbnailFilename = nil
                return copy
            }
            if includeImagesAndDocuments {
                for item in eligible {
                    try await collectAssets(for: item, storage: storage, into: &assets)
                }
            }
        }

        let archive = ClipboardArchive(
            version: ClipboardArchive.currentVersion,
            createdAt: .now,
            mode: mode,
            items: archiveItems,
            assets: assets,
            collections: collections,
            itemHashes: try Dictionary(
                uniqueKeysWithValues: archiveItems.map {
                    ($0.id.uuidString.lowercased(), try itemChecksum($0))
                }
            ),
            assetHashes: assets.mapValues { HashUtility.sha256(data: $0) },
            collectionHashes: try Dictionary(
                uniqueKeysWithValues: collections.map {
                    ($0.id.uuidString.lowercased(), try collectionChecksum($0))
                }
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(archive)
        let output = mode == .encrypted
            ? try PasswordArchiveCrypto.encrypt(encoded, password: password ?? "")
            : encoded
        try output.write(to: destination, options: .atomic)
        AppLog.storage.notice("Archive export completed; mode=\(mode.rawValue); items=\(archiveItems.count)")
    }

    func importArchive(
        from source: URL,
        password: String? = nil,
        storage: StorageService,
        existingItems: [ClipboardItem],
        encryptionMode: EncryptionMode
    ) async throws -> ImportReport {
        let resourceValues = try source.resourceValues(
            forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        )
        guard resourceValues.isSymbolicLink != true,
              resourceValues.isRegularFile == true else {
            throw ExportImportError.unsafePath
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let fileSize = attributes[.size] as? NSNumber
        guard fileSize?.intValue ?? 0 <= maximumArchiveBytes else {
            throw ExportImportError.archiveTooLarge
        }
        let raw = try Data(contentsOf: source, options: .mappedIfSafe)
        let encoded = PasswordArchiveCrypto.isEncryptedArchive(raw)
            ? try PasswordArchiveCrypto.decrypt(raw, password: password ?? "")
            : raw
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let archive = try? decoder.decode(ClipboardArchive.self, from: encoded) else {
            throw ExportImportError.invalidArchive
        }
        guard (1...ClipboardArchive.currentVersion).contains(archive.version) else {
            throw ExportImportError.unsupportedVersion
        }
        guard archive.mode != .metadataOnly else { throw ExportImportError.invalidArchive }
        guard archive.items.count <= maximumItemCount else { throw ExportImportError.archiveTooLarge }
        try validateAssetPaths(archive.assets.keys)
        try validateArchiveIntegrity(archive)
        try await storage.upsertCollectionsBatchThrowing(archive.collections)

        var hashes = Set(existingItems.map(\.hash))
        var imported = 0
        var duplicates = 0
        var rejected = 0
        for item in archive.items {
            guard !item.hash.isEmpty else {
                rejected += 1
                continue
            }
            guard hashes.insert(item.hash).inserted else {
                duplicates += 1
                continue
            }
            do {
                let importedItem = try await materialize(
                    item: item,
                    assets: archive.assets,
                    storage: storage,
                    encryptionMode: encryptionMode
                )
                try await storage.upsertThrowing(importedItem)
                imported += 1
            } catch {
                rejected += 1
            }
        }
        AppLog.storage.notice("Archive import completed; imported=\(imported); duplicates=\(duplicates); rejected=\(rejected)")
        return ImportReport(importedCount: imported, duplicateCount: duplicates, rejectedCount: rejected)
    }

    func importArchiveAtomically(
        from source: URL,
        password: String,
        storage: StorageService,
        encryptionMode: EncryptionMode
    ) async throws -> ImportReport {
        let archive = try decodeAndValidateArchive(from: source, password: password)
        guard archive.mode == .encrypted else { throw ExportImportError.invalidArchive }
        var materializedItems: [ClipboardItem] = []
        do {
            for item in archive.items {
                materializedItems.append(
                    try await materialize(
                        item: item,
                        assets: archive.assets,
                        storage: storage,
                        encryptionMode: encryptionMode
                    )
                )
            }
            try await storage.importBatchThrowing(
                items: materializedItems,
                collections: archive.collections
            )
            let stored = try await storage.loadHistoryThrowing()
            let storedCollections = try await storage.loadCollectionsThrowing()
            guard Set(stored.map(\.hash)) == Set(materializedItems.map(\.hash)),
                  stored.count == materializedItems.count,
                  storedCollections.sorted(by: { $0.sortOrder < $1.sortOrder })
                    == archive.collections.sorted(by: { $0.sortOrder < $1.sortOrder }) else {
                throw ExportImportError.invalidArchive
            }
            return ImportReport(
                importedCount: materializedItems.count,
                duplicateCount: 0,
                rejectedCount: 0
            )
        } catch {
            try? await storage.deleteBatchThrowing(ids: materializedItems.map(\.id))
            await storage.deleteImages(for: materializedItems)
            throw error
        }
    }

    private func metadataOnlyItem(_ item: ClipboardItem) -> ClipboardItem {
        var copy = item
        copy.text = nil
        copy.imageFilename = nil
        copy.thumbnailFilename = nil
        copy.payloadFilename = nil
        copy.assetFilenames = []
        copy.fileURLs = []
        copy.fileBookmarks = []
        copy.isEncrypted = false
        return copy
    }

    private func collectAssets(
        for item: ClipboardItem,
        storage: StorageService,
        into assets: inout [String: Data]
    ) async throws {
        if let filename = item.imageFilename,
           let data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted) {
            assets["Images/\(filename)"] = data
        }
        for filename in item.assetFilenames {
            if let data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted) {
                assets["Images/\(filename)"] = data
            }
        }
        if let filename = item.payloadFilename,
           let data = await storage.payloadData(filename: filename, isEncrypted: item.isEncrypted) {
            assets["Payloads/\(filename)"] = data
        }
    }

    private func validateAssetPaths<S: Sequence>(_ paths: S) throws where S.Element == String {
        for path in paths {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2,
                  ["Images", "Payloads"].contains(String(components[0])),
                  !components[1].isEmpty,
                  components[1] != ".",
                  components[1] != "..",
                  !components[1].contains("\\") else {
                throw ExportImportError.unsafePath
            }
        }
    }

    private func validateArchiveIntegrity(_ archive: ClipboardArchive) throws {
        let totalAssetBytes = archive.assets.values.reduce(into: Int64(0)) { total, data in
            total += Int64(data.count)
        }
        guard totalAssetBytes <= Int64(maximumArchiveBytes),
              archive.assets.values.allSatisfy({ $0.count <= maximumAssetBytes }) else {
            throw ExportImportError.archiveTooLarge
        }
        guard archive.version >= 2 else { return }
        guard archive.itemHashes.count == archive.items.count,
              archive.assetHashes.count == archive.assets.count,
              archive.collectionHashes.count == archive.collections.count else {
            throw ExportImportError.invalidArchive
        }
        for item in archive.items {
            guard archive.itemHashes[item.id.uuidString.lowercased()] == (try itemChecksum(item)) else {
                throw ExportImportError.invalidArchive
            }
        }
        for (path, data) in archive.assets {
            guard archive.assetHashes[path] == HashUtility.sha256(data: data) else {
                throw ExportImportError.invalidArchive
            }
        }
        for collection in archive.collections {
            guard archive.collectionHashes[collection.id.uuidString.lowercased()]
                    == (try collectionChecksum(collection)) else {
                throw ExportImportError.invalidArchive
            }
        }
    }

    private func decodeAndValidateArchive(
        from source: URL,
        password: String
    ) throws -> ClipboardArchive {
        let resourceValues = try source.resourceValues(
            forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        )
        guard resourceValues.isSymbolicLink != true,
              resourceValues.isRegularFile == true else {
            throw ExportImportError.unsafePath
        }
        guard resourceValues.fileSize.map({ $0 <= maximumArchiveBytes }) == true else {
            throw ExportImportError.archiveTooLarge
        }
        let raw = try Data(contentsOf: source, options: .mappedIfSafe)
        let encoded = try PasswordArchiveCrypto.decrypt(raw, password: password)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(ClipboardArchive.self, from: encoded)
        guard archive.version == ClipboardArchive.currentVersion,
              archive.items.count <= maximumItemCount else {
            throw ExportImportError.unsupportedVersion
        }
        try validateAssetPaths(archive.assets.keys)
        try validateArchiveIntegrity(archive)
        return archive
    }

    private func itemChecksum(_ item: ClipboardItem) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return HashUtility.sha256(data: try encoder.encode(item))
    }

    private func collectionChecksum(_ collection: ClipboardCollection) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return HashUtility.sha256(data: try encoder.encode(collection))
    }

    private func materialize(
        item: ClipboardItem,
        assets: [String: Data],
        storage: StorageService,
        encryptionMode: EncryptionMode
    ) async throws -> ClipboardItem {
        var copy = item
        copy.id = UUID()
        copy.thumbnailFilename = nil
        copy.isEncrypted = encryptionMode == .all || (encryptionMode == .sensitive && item.isSensitive)
        copy.fileBookmarks = item.fileBookmarks

        if let oldName = item.imageFilename {
            guard let data = assets["Images/\(oldName)"],
                  let name = await storage.storeImage(data, id: copy.id, encrypt: copy.isEncrypted) else {
                throw ExportImportError.missingAsset
            }
            copy.imageFilename = name
        }
        if !item.assetFilenames.isEmpty {
            var names: [String] = []
            for (index, oldName) in item.assetFilenames.enumerated() {
                guard let data = assets["Images/\(oldName)"],
                      let name = await storage.storeImage(
                          data,
                          id: copy.id,
                          encrypt: copy.isEncrypted,
                          index: index
                      ) else { throw ExportImportError.missingAsset }
                names.append(name)
            }
            copy.assetFilenames = names
        }
        if let oldName = item.payloadFilename {
            guard let data = assets["Payloads/\(oldName)"] else {
                throw ExportImportError.missingAsset
            }
            let ext = URL(fileURLWithPath: oldName).pathExtension
            guard !ext.isEmpty,
                  let name = await storage.storePayload(
                      data,
                      id: copy.id,
                      extension: ext,
                      encrypt: copy.isEncrypted
                  ) else { throw ExportImportError.missingAsset }
            copy.payloadFilename = name
        }
        return copy
    }
}
