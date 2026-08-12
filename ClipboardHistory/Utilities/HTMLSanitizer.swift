import Foundation
import libxml2

enum HTMLSanitizer {
    private static let allowedElements: Set<String> = [
        "a", "b", "blockquote", "br", "code", "del", "div", "em",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "li", "ol",
        "p", "pre", "s", "span", "strong", "sub", "sup", "table", "tbody",
        "td", "th", "thead", "tr", "u", "ul"
    ]
    private static let voidElements: Set<String> = ["br", "hr"]
    private static let removableSubtrees: Set<String> = [
        "script", "style", "iframe", "object", "embed", "svg", "math",
        "img", "audio", "video", "source", "link", "meta"
    ]

    static func sanitize(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        guard String(data: data, encoding: .utf8) != nil else { return nil }
        let options = Int32(
            HTML_PARSE_RECOVER.rawValue
                | HTML_PARSE_NOERROR.rawValue
                | HTML_PARSE_NOWARNING.rawValue
                | HTML_PARSE_NONET.rawValue
                | HTML_PARSE_COMPACT.rawValue
        )
        let document = data.withUnsafeBytes { bytes -> htmlDocPtr? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return htmlReadMemory(
                baseAddress.assumingMemoryBound(to: CChar.self),
                Int32(data.count),
                nil,
                "UTF-8",
                options
            )
        }
        guard let document else { return nil }
        defer { xmlFreeDoc(document) }

        let root = xmlDocGetRootElement(document)
        let body = firstElement(named: "body", from: root) ?? root
        var sanitized = ""
        var child = body?.pointee.children
        while let node = child {
            sanitized += serialize(node)
            child = node.pointee.next
        }
        return Data(sanitized.utf8)
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
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func serialize(_ node: xmlNodePtr) -> String {
        switch node.pointee.type {
        case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
            return escapedHTML(string(from: node.pointee.content))
        case XML_ELEMENT_NODE:
            let name = string(from: node.pointee.name).lowercased()
            if removableSubtrees.contains(name) { return "" }

            var children = ""
            var child = node.pointee.children
            while let current = child {
                children += serialize(current)
                child = current.pointee.next
            }
            guard allowedElements.contains(name) else { return children }

            var attributes = ""
            if name == "a" {
                if let href = property(named: "href", on: node), isSafeLink(href) {
                    attributes += " href=\"\(escapedAttribute(href))\""
                }
                if let title = property(named: "title", on: node) {
                    attributes += " title=\"\(escapedAttribute(title))\""
                }
            }
            if voidElements.contains(name) { return "<\(name)>" }
            return "<\(name)\(attributes)>\(children)</\(name)>"
        default:
            return ""
        }
    }

    private static func firstElement(named name: String, from node: xmlNodePtr?) -> xmlNodePtr? {
        var current = node
        while let candidate = current {
            if candidate.pointee.type == XML_ELEMENT_NODE,
               string(from: candidate.pointee.name).caseInsensitiveCompare(name) == .orderedSame {
                return candidate
            }
            if let nested = firstElement(named: name, from: candidate.pointee.children) {
                return nested
            }
            current = candidate.pointee.next
        }
        return nil
    }

    private static func property(named name: String, on node: xmlNodePtr) -> String? {
        var attribute = node.pointee.properties
        while let candidate = attribute {
            if string(from: candidate.pointee.name).caseInsensitiveCompare(name) == .orderedSame {
                return string(from: candidate.pointee.children?.pointee.content)
            }
            attribute = candidate.pointee.next
        }
        return nil
    }

    private static func isSafeLink(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("#") { return true }
        guard let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() else {
            return !trimmed.hasPrefix("//")
        }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func string(from value: UnsafePointer<xmlChar>?) -> String {
        guard let value else { return "" }
        return String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }

    private static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedAttribute(_ value: String) -> String {
        escapedHTML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
