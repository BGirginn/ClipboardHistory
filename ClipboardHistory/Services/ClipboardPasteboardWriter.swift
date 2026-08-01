import AppKit
import Foundation

@MainActor
final class ClipboardPasteboardWriter: ClipboardWriting, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func write(
        content: ClipboardContent,
        representation: PasteRepresentation
    ) async -> Bool {
        switch content {
        case let .text(value, rtfData, htmlData, _, _, _):
            return writeText(
                value,
                rtfData: rtfData,
                htmlData: htmlData,
                representation: representation
            )
        case let .images(pngData, _, _):
            return writeImages(pngData)
        case let .pdf(data, _, _):
            return writePDF(data)
        case let .files(urls, _, _, _):
            return writeFiles(urls)
        }
    }

    func write(
        item: ClipboardItem,
        storage: StorageService,
        representation: PasteRepresentation
    ) async -> Bool {
        if representation == .plainText,
           let extracted = item.protectedMetadata.qrCodeText
            ?? item.protectedMetadata.extractedText {
            return writeText(extracted, rtfData: nil, htmlData: nil, representation: .plainText)
        }

        switch item.type {
        case .text:
            guard let text = item.text else { return false }
            return writeText(text, rtfData: nil, htmlData: nil, representation: representation)
        case .richText:
            guard let text = item.text else { return false }
            let payload = await richTextPayload(for: item, storage: storage)
            return writeText(
                text,
                rtfData: payload?.rtfData,
                htmlData: payload?.htmlData,
                representation: representation
            )
        case .image:
            guard let filename = item.imageFilename,
                  let data = await storage.imageData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return false }
            return writeImages([data])
        case .imageGroup:
            var images: [Data] = []
            for filename in item.assetFilenames {
                if let data = await storage.imageData(
                    filename: filename,
                    isEncrypted: item.isEncrypted
                ) {
                    images.append(data)
                }
            }
            return images.count == item.assetFilenames.count && writeImages(images)
        case .pdf:
            guard let filename = item.payloadFilename,
                  let data = await storage.payloadData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return false }
            return writePDF(data)
        case .files:
            return writeFiles(resolveFileURLs(for: item))
        }
    }

    private func richTextPayload(
        for item: ClipboardItem,
        storage: StorageService
    ) async -> RichTextPayload? {
        guard let filename = item.payloadFilename,
              let data = await storage.payloadData(
                  filename: filename,
                  isEncrypted: item.isEncrypted
              ) else { return nil }
        if let payload = try? JSONDecoder().decode(RichTextPayload.self, from: data) {
            return payload
        }
        return filename.hasSuffix(".html")
            ? RichTextPayload(rtfData: nil, htmlData: data)
            : RichTextPayload(rtfData: data, htmlData: nil)
    }

    private func writeText(
        _ text: String,
        rtfData: Data?,
        htmlData: Data?,
        representation: PasteRepresentation
    ) -> Bool {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(text, forType: .string)
        switch representation {
        case .original:
            if let rtfData { pasteboardItem.setData(rtfData, forType: .rtf) }
            if let htmlData { pasteboardItem.setData(htmlData, forType: .html) }
        case .richText:
            if let rtfData { pasteboardItem.setData(rtfData, forType: .rtf) }
        case .html:
            if let htmlData, let cleaned = HTMLSanitizer.sanitize(htmlData) {
                pasteboardItem.setData(cleaned, forType: .html)
            }
        case .plainText:
            break
        }
        _ = pasteboard.clearContents()
        return pasteboard.writeObjects([pasteboardItem])
    }

    private func writeImages(_ pngData: [Data]) -> Bool {
        let objects = pngData.compactMap { data -> NSPasteboardItem? in
            guard let image = NSImage(data: data), let tiff = image.tiffRepresentation else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            item.setData(tiff, forType: .tiff)
            return item
        }
        guard objects.count == pngData.count else { return false }
        _ = pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }

    private func writePDF(_ data: Data) -> Bool {
        let item = NSPasteboardItem()
        item.setData(data, forType: .pdf)
        _ = pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private func writeFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        _ = pasteboard.clearContents()
        return pasteboard.writeObjects(urls as [NSURL])
    }

    private func resolveFileURLs(for item: ClipboardItem) -> [URL] {
        var resolved: [URL] = []
        for bookmark in item.fileBookmarks {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                resolved.append(url)
            }
        }
        if resolved.isEmpty {
            resolved = item.fileURLs.map { URL(fileURLWithPath: $0) }
        }
        return resolved.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
