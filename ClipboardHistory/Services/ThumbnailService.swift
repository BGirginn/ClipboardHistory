import AppKit
import Foundation
import ImageIO
import PDFKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSData>()

    init(cacheMegabytes: Int = 64) {
        cache.totalCostLimit = max(8, cacheMegabytes) * 1_024 * 1_024
        cache.countLimit = 256
    }

    func setCacheLimit(megabytes: Int) {
        cache.totalCostLimit = max(8, megabytes) * 1_024 * 1_024
    }

    func thumbnailData(for item: ClipboardItem, storage: StorageService) async -> Data? {
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return Data(referencing: cached)
        }

        if let filename = item.thumbnailFilename,
           let existing = await storage.thumbnailData(
               filename: filename,
               isEncrypted: item.isEncrypted
           ) {
            cache(existing, for: key)
            return existing
        }

        guard let generated = await generateThumbnail(for: item, storage: storage) else { return nil }
        if let filename = item.thumbnailFilename {
            _ = await storage.storeThumbnail(
                generated,
                filename: filename,
                encrypt: item.isEncrypted
            )
        }
        cache(generated, for: key)
        return generated
    }

    func invalidate(itemID: UUID) {
        cache.removeObject(forKey: itemID.uuidString as NSString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    private func generateThumbnail(
        for item: ClipboardItem,
        storage: StorageService
    ) async -> Data? {
        switch item.type {
        case .image:
            guard let filename = item.imageFilename,
                  let data = await storage.imageData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return nil }
            return imageThumbnail(data)

        case .imageGroup:
            guard let filename = item.assetFilenames.first,
                  let data = await storage.imageData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return nil }
            return imageThumbnail(data)

        case .pdf:
            guard let filename = item.payloadFilename,
                  let data = await storage.payloadData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ),
                  let document = PDFDocument(data: data),
                  let page = document.page(at: 0) else { return nil }
            let image = page.thumbnail(of: NSSize(width: 160, height: 120), for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])

        case .text, .richText, .files:
            return nil
        }
    }

    private func imageThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maximumDimension = min(320, max(width, height))
        guard maximumDimension > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func cache(_ data: Data, for key: NSString) {
        cache.setObject(data as NSData, forKey: key, cost: data.count)
    }
}
