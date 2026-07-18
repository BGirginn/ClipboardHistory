import Foundation

enum HTMLSanitizer {
    static func sanitize(_ data: Data) -> Data? {
        guard var html = String(data: data, encoding: .utf8) else { return nil }
        let destructivePatterns = [
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            #"(?is)<(iframe|object|embed)\b[^>]*>.*?</\1\s*>"#,
            #"(?is)<(iframe|object|embed)\b[^>]*/?>"#,
            #"(?i)\s+on[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)"#,
            #"(?i)\s+(src|href)\s*=\s*(\"|')\s*(https?:)?//[^\"']*\2"#
        ]
        for pattern in destructivePatterns {
            html = html.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return Data(html.utf8)
    }

    static func plainText(fromSanitizedHTML html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"(?is)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
