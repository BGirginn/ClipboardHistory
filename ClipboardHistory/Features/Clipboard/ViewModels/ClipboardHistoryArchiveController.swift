import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel {
    func performImageExport(_ item: ClipboardItem, asJPEG: Bool) async {
        guard let filename = item.imageFilename ?? item.assetFilenames.first,
              let pngData = await storage.imageData(
                  filename: filename,
                  isEncrypted: item.isEncrypted
              ) else { return }
        guard let destination = await archivePanelSelector.saveDestination(
            suggestedName: asJPEG ? "Clipboard Image.jpg" : "Clipboard Image.png",
            allowedTypes: asJPEG ? [.jpeg] : [.png]
        ) else { return }
        do {
            let output = asJPEG ? try jpegData(from: pngData) : pngData
            try output.write(to: destination, options: .atomic)
        } catch {
            errorMessage = String(localized: "Image export failed: \(error.localizedDescription)")
        }
    }

    func performArchiveExport(
        mode: ClipboardExportMode,
        includeImagesAndDocuments: Bool,
        includeFileReferences: Bool,
        password: String?
    ) async {
        guard let destination = await archivePanelSelector.saveDestination(
            suggestedName: mode == .encrypted
                ? "ClipboardHistory-Encrypted.clipboardarchive"
                : "ClipboardHistory.clipboardarchive",
            allowedTypes: [.data]
        ) else { return }
        do {
            let notes = try await storage.loadNotesThrowing()
            try await exportImportService.exportArchive(
                items: items,
                storage: storage,
                to: destination,
                mode: mode,
                includeImagesAndDocuments: includeImagesAndDocuments,
                includeFileReferences: includeFileReferences,
                collections: collections,
                notes: notes,
                password: password
            )
            archiveStatusMessage = String(localized: "Export completed.")
        } catch {
            archiveStatusMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    func performArchiveImport(password: String?) async {
        guard let source = await archivePanelSelector.openSource(
            allowedTypes: [.data]
        ) else { return }
        do {
            let report = try await exportImportService.importArchive(
                from: source,
                password: password,
                storage: storage,
                existingItems: items,
                encryptionMode: .off
            )
            let temporary = items.filter { temporaryContent[$0.id] != nil }
            items = temporary + (await storage.loadHistory())
            await notesDidImport?()
            refreshDisplayedItems()
            archiveStatusMessage = String(localized: "Imported \(report.importedCount) clipboard items and \(report.importedNoteCount) notes; skipped \(report.duplicateCount + report.duplicateNoteCount) duplicates.")
        } catch {
            archiveStatusMessage = String(localized: "Import failed: \(error.localizedDescription)")
        }
    }

    func performStorageRecoveryImport(password: String) async {
        guard !password.isEmpty else {
            archiveStatusMessage = String(localized: "The recovery archive password is required.")
            return
        }
        guard let source = await archivePanelSelector.openSource(
            allowedTypes: [.data]
        ) else { return }
        stopMonitoring()
        await cancelAndAwaitAllPendingWrites()
        await storage.close()
        do {
            let result = try await storageRecoveryImporter.migrate(
                encryptedArchive: source,
                password: password,
                to: StorageService.defaultBaseDirectory()
            )
            isStorageAvailable = false
            archiveStatusMessage = String(localized: "Recovered \(result.importedItemCount) clipboard items and \(result.importedNoteCount) notes. The previous database was preserved for rollback. Quit and reopen Clipboard History to finish.")
        } catch let recoveryError as StorageRecoveryError {
            isStorageAvailable = false
            if recoveryError.previousDatabaseRestored {
                archiveStatusMessage = String(localized: "Recovery failed and the previous database was restored: \(recoveryError.localizedDescription). Quit and reopen Clipboard History.")
            } else {
                archiveStatusMessage = String(localized: "Recovery failed and rollback could not be verified: \(recoveryError.localizedDescription). Do not relaunch until the rollback backup is inspected.")
            }
        } catch {
            isStorageAvailable = false
            archiveStatusMessage = String(localized: "Recovery failed before replacing the previous database: \(error.localizedDescription). Quit and reopen Clipboard History.")
        }
    }

    func jpegData(
        from pngData: Data,
        encoder: (NSBitmapImageRep) -> Data? = {
            $0.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    ) throws -> Data {
        guard let source = NSImage(data: pngData) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let composited = NSImage(size: source.size)
        composited.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: source.size).fill()
        source.draw(in: NSRect(origin: .zero, size: source.size))
        composited.unlockFocus()
        guard let tiff = composited.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = encoder(bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return jpeg
    }
}
