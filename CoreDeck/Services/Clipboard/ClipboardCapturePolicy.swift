import Foundation
import ImageIO

enum ClipboardCapturePolicy {
    static let maximumTextBytes = 1 * 1_024 * 1_024
    static let maximumRichContentBytes = 8 * 1_024 * 1_024
    static let maximumRepresentationBytes = 64 * 1_024 * 1_024
    static let maximumTotalBytes = 128 * 1_024 * 1_024
    static let maximumItemCount = 32
    static let maximumImagePixels = 100_000_000
    static let maximumImageDimension = 16_384

    static func validateItemCount(_ count: Int) throws {
        guard count <= maximumItemCount else {
            throw ClipboardCapturePolicyViolation.tooManyItems
        }
    }

    static func validateText(_ value: String) throws {
        guard value.utf8.count <= maximumTextBytes else {
            throw ClipboardCapturePolicyViolation.textTooLarge
        }
    }

    static func validateRichContent(_ data: Data?) throws {
        guard let data else { return }
        guard data.count <= maximumRichContentBytes else {
            throw ClipboardCapturePolicyViolation.richContentTooLarge
        }
    }

    static func validateBinaryRepresentation(_ data: Data) throws {
        guard data.count <= maximumRepresentationBytes else {
            throw ClipboardCapturePolicyViolation.representationTooLarge
        }
    }

    static func validateTotalBytes(_ count: Int) throws {
        guard count <= maximumTotalBytes else {
            throw ClipboardCapturePolicyViolation.captureTooLarge
        }
    }

    static func validateImageDimensions(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return }
        let pixelWidth = width.intValue
        let pixelHeight = height.intValue
        guard pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= maximumImageDimension,
              pixelHeight <= maximumImageDimension,
              pixelWidth <= maximumImagePixels / pixelHeight else {
            throw ClipboardCapturePolicyViolation.imageDimensionsTooLarge
        }
    }
}
