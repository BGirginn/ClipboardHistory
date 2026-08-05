import Foundation

struct ImportReport: Equatable, Sendable {
    let importedCount: Int
    let duplicateCount: Int
    let rejectedCount: Int
    let importedNoteCount: Int
    let duplicateNoteCount: Int
    let rejectedNoteCount: Int

    init(
        importedCount: Int,
        duplicateCount: Int,
        rejectedCount: Int,
        importedNoteCount: Int = 0,
        duplicateNoteCount: Int = 0,
        rejectedNoteCount: Int = 0
    ) {
        self.importedCount = importedCount
        self.duplicateCount = duplicateCount
        self.rejectedCount = rejectedCount
        self.importedNoteCount = importedNoteCount
        self.duplicateNoteCount = duplicateNoteCount
        self.rejectedNoteCount = rejectedNoteCount
    }
}
