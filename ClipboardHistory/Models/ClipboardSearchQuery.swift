import Foundation

struct ClipboardSearchQuery: Sendable {
    private let terms: [Term]

    init(_ text: String) {
        terms = text.split(whereSeparator: \.isWhitespace).map(Self.parse)
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ item: ClipboardItem, collectionName: String?) -> Bool {
        terms.allSatisfy { term in
            switch term {
            case let .any(value):
                return searchableText(for: item, collectionName: collectionName)
                    .localizedStandardContains(value)
            case let .source(value):
                return item.sourceApplicationBundleID?.localizedStandardContains(value) == true
            case let .type(value):
                return item.type.rawValue.localizedStandardContains(value)
                    || item.contentSubtype.rawValue.localizedStandardContains(value)
            case let .collection(value):
                return collectionName?.localizedStandardContains(value) == true
            case let .tag(value):
                return item.protectedMetadata.tags.contains {
                    $0.localizedStandardContains(value)
                }
            case let .recognizedText(value):
                return [item.protectedMetadata.extractedText, item.protectedMetadata.qrCodeText]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .localizedStandardContains(value)
            case let .after(date):
                return item.creationDate >= date
            case let .before(date):
                return item.creationDate < date
            case .invalid:
                return false
            }
        }
    }

    private func searchableText(for item: ClipboardItem, collectionName: String?) -> String {
        [
            item.text,
            item.displayTitle,
            item.type.rawValue,
            item.contentSubtype.rawValue,
            item.sourceApplicationBundleID,
            item.protectedMetadata.extractedText,
            item.protectedMetadata.qrCodeText,
            item.protectedMetadata.colorHex,
            item.protectedMetadata.tags.joined(separator: " "),
            collectionName
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func parse(_ token: Substring) -> Term {
        guard let separator = token.firstIndex(of: ":") else {
            return .any(String(token))
        }
        let field = token[..<separator].lowercased()
        let valueStart = token.index(after: separator)
        let value = String(token[valueStart...])
        guard !value.isEmpty else { return .invalid }
        switch field {
        case "app", "source": return .source(value)
        case "type", "kind": return .type(value)
        case "collection": return .collection(value)
        case "tag": return .tag(value)
        case "ocr", "qr": return .recognizedText(value)
        case "after": return dayBoundary(value).map(Term.after) ?? .invalid
        case "before": return dayBoundary(value).map(Term.before) ?? .invalid
        default: return .any(String(token))
        }
    }

    private static func dayBoundary(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private enum Term: Sendable {
        case any(String)
        case source(String)
        case type(String)
        case collection(String)
        case tag(String)
        case recognizedText(String)
        case after(Date)
        case before(Date)
        case invalid
    }
}
