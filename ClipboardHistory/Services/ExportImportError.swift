import Foundation

enum ExportImportError: LocalizedError, Sendable {
    case passwordRequired
    case invalidArchive
    case unsupportedVersion
    case unsafePath
    case archiveTooLarge
    case missingAsset

    var errorDescription: String? {
        switch self {
        case .passwordRequired: "A password is required for this encrypted archive."
        case .invalidArchive: "The selected file is not a valid Clipboard History archive."
        case .unsupportedVersion: "This Clipboard History archive version is unsupported."
        case .unsafePath: "The archive contains an unsafe asset path."
        case .archiveTooLarge: "The archive exceeds the safe import limit."
        case .missingAsset: "The archive is missing required content."
        }
    }
}
