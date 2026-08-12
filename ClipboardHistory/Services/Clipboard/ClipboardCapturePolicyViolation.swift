import Foundation

enum ClipboardCapturePolicyViolation: LocalizedError, Equatable, Sendable {
    case tooManyItems
    case textTooLarge
    case richContentTooLarge
    case representationTooLarge
    case captureTooLarge
    case imageDimensionsTooLarge

    var errorDescription: String? {
        switch self {
        case .tooManyItems:
            "Clipboard capture was skipped because it contains more than 32 items."
        case .textTooLarge:
            "Clipboard capture was skipped because its text is larger than 1 MiB."
        case .richContentTooLarge:
            "Clipboard capture was skipped because its rich-text data is larger than 8 MiB."
        case .representationTooLarge:
            "Clipboard capture was skipped because one representation is larger than 64 MiB."
        case .captureTooLarge:
            "Clipboard capture was skipped because its total size is larger than 128 MiB."
        case .imageDimensionsTooLarge:
            "Clipboard capture was skipped because an image exceeds 100 MP or 16,384 pixels per side."
        }
    }
}
