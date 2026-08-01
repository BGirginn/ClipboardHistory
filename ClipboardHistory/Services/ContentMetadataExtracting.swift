import Foundation

protocol ContentMetadataExtracting: Sendable {
    func dimensions(forFirstImage images: [Data]) async -> ImageDimensions?
    func pageCount(forPDF data: Data) async -> Int?
}
