import Foundation

struct ClipboardCollection: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var creationDate: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        creationDate: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.sortOrder = sortOrder
    }
}
