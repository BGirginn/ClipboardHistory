import Foundation

enum PasteRepresentation: String, CaseIterable, Identifiable, Sendable {
    case original
    case plainText
    case richText
    case html

    var id: Self { self }

    var title: String {
        switch self {
        case .original: String(localized: "Original")
        case .plainText: String(localized: "Plain Text")
        case .richText: String(localized: "RTF")
        case .html: String(localized: "Clean HTML")
        }
    }
}
