import Foundation

enum TextTransformation: String, CaseIterable, Identifiable, Sendable {
    case uppercase
    case lowercase
    case titleCase
    case trimWhitespace

    var id: Self { self }

    var title: String {
        switch self {
        case .uppercase: String(localized: "Uppercase")
        case .lowercase: String(localized: "Lowercase")
        case .titleCase: String(localized: "Title Case")
        case .trimWhitespace: String(localized: "Trim Surrounding Whitespace")
        }
    }

    func apply(to text: String, locale: Locale = .current) -> String {
        switch self {
        case .uppercase:
            text.uppercased(with: locale)
        case .lowercase:
            text.lowercased(with: locale)
        case .titleCase:
            text.capitalized(with: locale)
        case .trimWhitespace:
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
