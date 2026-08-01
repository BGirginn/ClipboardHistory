import Foundation

enum PasteStackOrder: String, CaseIterable, Codable, Identifiable, Sendable {
    case fifo
    case lifo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifo: String(localized: "First In, First Out")
        case .lifo: String(localized: "Last In, First Out")
        }
    }
}
