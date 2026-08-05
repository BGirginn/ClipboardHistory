import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardDragProviderFactory {
    @MainActor
    static func make(for item: ClipboardItem, storage: StorageService) -> NSItemProvider {
        switch item.type {
        case .text, .richText:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .files:
            guard let path = item.fileURLs.first,
                  let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) else {
                return NSItemProvider()
            }
            return provider
        case .image, .imageGroup:
            let provider = NSItemProvider()
            guard let filename = item.imageFilename ?? item.assetFilenames.first else {
                return provider
            }
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.png.identifier,
                visibility: .all
            ) { completion in
                Task {
                    let data = await storage.imageData(
                        filename: filename,
                        isEncrypted: item.isEncrypted
                    )
                    completion(data, data == nil ? CocoaError(.fileReadNoSuchFile) : nil)
                }
                return nil
            }
            return provider
        case .pdf:
            let provider = NSItemProvider()
            guard let filename = item.payloadFilename else { return provider }
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.pdf.identifier,
                visibility: .all
            ) { completion in
                Task {
                    let data = await storage.payloadData(
                        filename: filename,
                        isEncrypted: item.isEncrypted
                    )
                    completion(data, data == nil ? CocoaError(.fileReadNoSuchFile) : nil)
                }
                return nil
            }
            return provider
        }
    }
}
