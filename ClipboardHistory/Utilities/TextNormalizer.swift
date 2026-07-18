import Foundation

enum TextNormalizer {
    static func normalizedForHash(_ text: String, trimTrailingWhitespace: Bool = true) -> String {
        let normalizedLines = text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")

        guard trimTrailingWhitespace else { return normalizedLines }
        return normalizedLines.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()
            }
            .map(String.init)
            .joined(separator: "\n")
    }

    static func normalizedURLForHash(_ text: String) -> String? {
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased() else { return nil }

        components.scheme = scheme
        components.host = host
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        return components.string
    }
}
