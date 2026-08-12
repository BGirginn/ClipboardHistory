import Foundation

enum MemoryMetricFormat: String, Codable, CaseIterable, Identifiable {
    case percentage
    case usedAndTotal
    var id: String { rawValue }
}
