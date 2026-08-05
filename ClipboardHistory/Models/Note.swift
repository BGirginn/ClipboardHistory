import Foundation

struct Note: Codable, Equatable, Identifiable, Sendable {
    static let maximumTitleLength = 200
    static let maximumBodyBytes = 1_048_576

    var id: UUID
    var title: String?
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var resolvedTitle: String? {
        if let title = normalizedTitle, !title.isEmpty {
            return title
        }
        return body
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .map { String($0.prefix(Self.maximumTitleLength)) }
    }

    var normalizedTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasContent: Bool {
        normalizedTitle != nil || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
