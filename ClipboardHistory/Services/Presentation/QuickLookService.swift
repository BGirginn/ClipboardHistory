import AppKit
import Foundation
import QuickLookUI

@MainActor
final class QuickLookService: NSObject, QuickLookPresenting, @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    private var previewURLs: [URL] = []
    private var temporaryDirectory: URL?
    private let panelProvider: () -> (any QuickLookPanelControlling)?
    private let temporaryDirectoryProvider: () -> URL

    init(
        panelProvider: @escaping () -> (any QuickLookPanelControlling)? = {
            guard let panel = QLPreviewPanel.shared() else { return nil }
            return SystemQuickLookPanelController(panel: panel)
        },
        temporaryDirectoryProvider: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
        }
    ) {
        self.panelProvider = panelProvider
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
    }

    func show(item: ClipboardItem, storage: StorageService) {
        Task { [weak self] in
            guard let self else { return }
            cleanupTemporaryFiles()
            let urls = await materializePreviewURLs(for: item, storage: storage)
            guard !urls.isEmpty else { return }
            previewURLs = urls
            guard let panel = panelProvider() else { return }
            panel.present(dataSource: self, delegate: self)
        }
    }

    func close() {
        panelProvider()?.orderOut()
        cleanupTemporaryFiles()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        cleanupTemporaryFiles()
    }

    private func materializePreviewURLs(
        for item: ClipboardItem,
        storage: StorageService
    ) async -> [URL] {
        if item.type == .files {
            return item.fileURLs.map { URL(fileURLWithPath: $0) }.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }

        var payloads: [(String, Data)] = []
        switch item.type {
        case .image:
            if let filename = item.imageFilename,
               let data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted) {
                payloads.append((filename, data))
            }
        case .imageGroup:
            for filename in item.assetFilenames {
                if let data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted) {
                    payloads.append((filename, data))
                }
            }
        case .pdf, .richText:
            if let filename = item.payloadFilename,
               let data = await storage.payloadData(filename: filename, isEncrypted: item.isEncrypted) {
                payloads.append((filename, data))
            }
        case .text, .files:
            break
        }
        guard !payloads.isEmpty else { return [] }

        let directory = temporaryDirectoryProvider().appending(
            path: "ClipboardHistoryPreview-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls: [URL] = []
            for (filename, data) in payloads {
                let destination = directory.appending(path: filename, directoryHint: .notDirectory)
                try data.write(to: destination, options: .atomic)
                urls.append(destination)
            }
            temporaryDirectory = directory
            return urls
        } catch {
            AppLog.storage.error(
                "Quick Look materialization failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            try? FileManager.default.removeItem(at: directory)
            return []
        }
    }

    private func cleanupTemporaryFiles() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        previewURLs = []
    }
}
