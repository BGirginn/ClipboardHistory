import Foundation

enum ExportImportError: LocalizedError, Sendable {
    case passwordRequired
    case invalidArchive
    case unsupportedVersion
    case unsafePath
    case archiveTooLarge
    case missingAsset
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .passwordRequired: String(localized: "A password is required for this encrypted archive.")
        case .invalidArchive: String(localized: "The selected file is not a valid CoreDeck archive.")
        case .unsupportedVersion: String(localized: "This CoreDeck archive version is unsupported.")
        case .unsafePath: String(localized: "The archive contains an unsafe asset path.")
        case .archiveTooLarge: String(localized: "The archive exceeds the safe import limit.")
        case .missingAsset: String(localized: "The archive is missing required content.")
        case .cleanupFailed: String(localized: "Import failed and some created files could not be removed. Retry storage cleanup before importing again.")
        }
    }
}
