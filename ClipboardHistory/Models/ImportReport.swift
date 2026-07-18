import Foundation

struct ImportReport: Equatable, Sendable {
    let importedCount: Int
    let duplicateCount: Int
    let rejectedCount: Int
}
