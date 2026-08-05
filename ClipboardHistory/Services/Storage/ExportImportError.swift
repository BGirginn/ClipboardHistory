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
        case .passwordRequired: String(localized: "A password is required for this encrypted archive.")
        case .invalidArchive: String(localized: "The selected file is not a valid Clipboard History archive.")
        case .unsupportedVersion: String(localized: "This Clipboard History archive version is unsupported.")
        case .unsafePath: String(localized: "The archive contains an unsafe asset path.")
        case .archiveTooLarge: String(localized: "The archive exceeds the safe import limit.")
        case .missingAsset: String(localized: "The archive is missing required content.")
        }
    }
}
