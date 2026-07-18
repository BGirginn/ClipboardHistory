import Foundation

enum TextClassifier {
    static func subtype(for text: String) -> ClipboardContentSubtype {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if TextNormalizer.normalizedURLForHash(trimmed) != nil {
            return .url
        }
        if trimmed.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .email
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return .filePath
        }
        let codeSignals = ["func ", "class ", "struct ", "import ", "const ", "let ", "=>", "</"]
        if codeSignals.contains(where: { trimmed.localizedStandardContains($0) })
            || (trimmed.contains("{") && trimmed.contains("}")) {
            return .sourceCode
        }
        return .plainText
    }
}
