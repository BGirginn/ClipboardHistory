import AppKit
import Foundation
import ImageIO
import PDFKit

actor ThumbnailService {
    typealias ImageThumbnailCreator = @Sendable (CGImageSource, Int, CFDictionary?) -> CGImage?

    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSData>()
    private var inFlightRequests: [UUID: Task<Data?, Never>] = [:]
    private var requestTokens: [UUID: UUID] = [:]
    private let imageThumbnailCreator: ImageThumbnailCreator

    init(
        cacheMegabytes: Int = 64,
        imageThumbnailCreator: @escaping ImageThumbnailCreator = CGImageSourceCreateThumbnailAtIndex
    ) {
        self.imageThumbnailCreator = imageThumbnailCreator
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

        if let request = inFlightRequests[item.id] {
            return await request.value
        }

        let token = UUID()
        let request = Task { [item, storage] in
            await self.loadThumbnailData(for: item, storage: storage)
        }
        inFlightRequests[item.id] = request
        requestTokens[item.id] = token
        let data = await request.value
        guard requestTokens[item.id] == token else { return data }
        inFlightRequests[item.id] = nil
        requestTokens[item.id] = nil
        if let data {
            cache(data, for: key)
        }
        return data
    }

    func invalidate(itemID: UUID) {
        inFlightRequests[itemID]?.cancel()
        inFlightRequests[itemID] = nil
        requestTokens[itemID] = nil
        cache.removeObject(forKey: itemID.uuidString as NSString)
    }

    func clearCache() {
        inFlightRequests.values.forEach { $0.cancel() }
        inFlightRequests.removeAll()
        requestTokens.removeAll()
        cache.removeAllObjects()
    }

    private func loadThumbnailData(
        for item: ClipboardItem,
        storage: StorageService
    ) async -> Data? {
        if let filename = item.thumbnailFilename,
           let existing = await storage.thumbnailData(
               filename: filename,
               isEncrypted: item.isEncrypted
           ) {
            return existing
        }

        guard !Task.isCancelled else { return nil }
        guard let generated = await generateThumbnail(for: item, storage: storage) else { return nil }
        guard !Task.isCancelled else { return nil }
        if let filename = item.thumbnailFilename {
            _ = await storage.storeThumbnail(
                generated,
                filename: filename,
                encrypt: item.isEncrypted
            )
        }
        return generated
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
        guard let image = imageThumbnailCreator(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func cache(_ data: Data, for key: NSString) {
        cache.setObject(data as NSData, forKey: key, cost: data.count)
    }
}
