import Foundation
import PDFKit

actor ContentMetadataService: ContentMetadataExtracting {
    func dimensions(forFirstImage images: [Data]) -> ImageDimensions? {
        guard let dimensions = images.first.flatMap(ImageMetadataUtility.dimensions) else {
            return nil
        }
        return ImageDimensions(width: dimensions.width, height: dimensions.height)
    }

    func pageCount(forPDF data: Data) -> Int? {
        PDFDocument(data: data)?.pageCount
    }
}
