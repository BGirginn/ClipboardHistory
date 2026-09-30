import AppKit
import Foundation

actor ClipboardProcessingService: ClipboardContentProcessing {
    func process(
        _ rawContent: ClipboardRawContent,
        sourceBundleIdentifier: String?
    ) async -> ClipboardContent? {
        switch rawContent {
        case let .text(value, rtfData, htmlData):
            let subtype = TextClassifier.subtype(for: value)
            let safeHTML = htmlData.flatMap(HTMLSanitizer.sanitize)
            let canonical: Data
            if let safeHTML {
                canonical = safeHTML
            } else if let rtfData {
                canonical = rtfData
            } else {
                let normalized = subtype == .url
                    ? TextNormalizer.normalizedURLForHash(value) ?? TextNormalizer.normalizedForHash(value)
                    : TextNormalizer.normalizedForHash(value)
                canonical = Data(normalized.utf8)
            }
            return .text(
                value: value,
                rtfData: rtfData,
                htmlData: safeHTML,
                subtype: safeHTML == nil && rtfData == nil ? subtype : (safeHTML == nil ? .rtf : .html),
                hash: HashUtility.sha256(data: canonical),
                sourceBundleIdentifier: sourceBundleIdentifier
            )

        case let .images(imageData):
            let pngData = imageData.compactMap(convertToPNG)
            guard !pngData.isEmpty else { return nil }
            return .images(
                pngData: pngData,
                hash: pngData.count == 1
                    ? HashUtility.sha256(data: pngData[0])
                    : HashUtility.sha256(orderedData: pngData),
                sourceBundleIdentifier: sourceBundleIdentifier
            )

        case let .pdf(data):
            guard data.starts(with: Data("%PDF".utf8)) else { return nil }
            return .pdf(
                data: data,
                hash: HashUtility.sha256(data: data),
                sourceBundleIdentifier: sourceBundleIdentifier
            )

        case let .files(urls, bookmarks):
            guard !urls.isEmpty else { return nil }
            let canonical = urls.map(fileIdentity).joined(separator: "\u{0}")
            return .files(
                urls: urls,
                bookmarks: bookmarks,
                hash: HashUtility.sha256(text: canonical),
                sourceBundleIdentifier: sourceBundleIdentifier
            )
        }
    }

    private func convertToPNG(_ data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return data
        }
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func fileIdentity(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [
            .fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey
        ])
        let identifier = values?.fileResourceIdentifier.map { String(describing: $0) } ?? ""
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)|\(identifier)|\(size)|\(modified)"
    }
}
