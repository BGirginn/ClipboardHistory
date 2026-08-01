import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ArchivePanelSelecting: AnyObject {
    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL?
    func openSource(allowedTypes: [UTType]) async -> URL?
}

@MainActor
protocol ArchiveSavePanelPresenting: AnyObject {
    var canCreateDirectories: Bool { get set }
    var nameFieldStringValue: String { get set }
    var allowedContentTypes: [UTType] { get set }
    var url: URL? { get }
    func begin() async -> NSApplication.ModalResponse
}

@MainActor
protocol ArchiveOpenPanelPresenting: AnyObject {
    var canChooseDirectories: Bool { get set }
    var allowsMultipleSelection: Bool { get set }
    var allowedContentTypes: [UTType] { get set }
    var url: URL? { get }
    func begin() async -> NSApplication.ModalResponse
}

extension NSSavePanel: ArchiveSavePanelPresenting {}
extension NSOpenPanel: ArchiveOpenPanelPresenting {}

@MainActor
final class SystemArchivePanelSelector: ArchivePanelSelecting {
    private let makeSavePanel: @MainActor () -> any ArchiveSavePanelPresenting
    private let makeOpenPanel: @MainActor () -> any ArchiveOpenPanelPresenting

    init(
        makeSavePanel: (@MainActor () -> any ArchiveSavePanelPresenting)? = nil,
        makeOpenPanel: (@MainActor () -> any ArchiveOpenPanelPresenting)? = nil
    ) {
        self.makeSavePanel = makeSavePanel ?? NSSavePanel.init
        self.makeOpenPanel = makeOpenPanel ?? NSOpenPanel.init
    }

    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL? {
        let panel = makeSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedTypes
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    func openSource(allowedTypes: [UTType]) async -> URL? {
        let panel = makeOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}

protocol StorageRecoveryImporting: Sendable {
    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult
}

struct SystemStorageRecoveryImporter: StorageRecoveryImporting {
    private let service: any StorageRecoveryImporting

    init(service: any StorageRecoveryImporting = StorageRecoveryImportService()) {
        self.service = service
    }

    func migrate(
        encryptedArchive: URL,
        password: String,
        to destinationDirectory: URL
    ) async throws -> StorageRecoveryImportResult {
        try await service.migrate(
            encryptedArchive: encryptedArchive,
            password: password,
            to: destinationDirectory
        )
    }
}

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
            try await exportImportService.exportArchive(
                items: items,
                storage: storage,
                to: destination,
                mode: mode,
                includeImagesAndDocuments: includeImagesAndDocuments,
                includeFileReferences: includeFileReferences,
                collections: collections,
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
                encryptionMode: settings.encryptionMode
            )
            let temporary = items.filter { temporaryContent[$0.id] != nil }
            items = temporary + (await storage.loadHistory())
            refreshDisplayedItems()
            archiveStatusMessage = String(localized: "Imported \(report.importedCount); skipped \(report.duplicateCount) duplicates.")
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
            archiveStatusMessage = String(localized: "Recovered \(result.importedItemCount) items. The previous database was preserved for rollback. Quit and reopen Clipboard History to finish.")
        } catch {
            isStorageAvailable = false
            archiveStatusMessage = String(localized: "Recovery failed without replacing the previous database: \(error.localizedDescription). Quit and reopen Clipboard History.")
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
