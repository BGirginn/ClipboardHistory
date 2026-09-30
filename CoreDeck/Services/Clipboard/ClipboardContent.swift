import Foundation

enum ClipboardContent: Equatable, Sendable {
    case text(
        value: String,
        rtfData: Data?,
        htmlData: Data?,
        subtype: ClipboardContentSubtype,
        hash: String,
        sourceBundleIdentifier: String?
    )
    case images(
        pngData: [Data],
        hash: String,
        sourceBundleIdentifier: String?
    )
    case pdf(
        data: Data,
        hash: String,
        sourceBundleIdentifier: String?
    )
    case files(
        urls: [URL],
        bookmarks: [Data],
        hash: String,
        sourceBundleIdentifier: String?
    )

    var hash: String {
        switch self {
        case let .text(_, _, _, _, hash, _),
             let .images(_, hash, _),
             let .pdf(_, hash, _),
             let .files(_, _, hash, _):
            hash
        }
    }

    var sourceBundleIdentifier: String? {
        switch self {
        case let .text(_, _, _, _, _, source),
             let .images(_, _, source),
             let .pdf(_, _, source),
             let .files(_, _, _, source):
            source
        }
    }

    static func text(value: String, hash: String) -> ClipboardContent {
        .text(
            value: value,
            rtfData: nil,
            htmlData: nil,
            subtype: TextClassifier.subtype(for: value),
            hash: hash,
            sourceBundleIdentifier: nil
        )
    }

    static func image(pngData: Data, hash: String) -> ClipboardContent {
        .images(pngData: [pngData], hash: hash, sourceBundleIdentifier: nil)
    }
}
