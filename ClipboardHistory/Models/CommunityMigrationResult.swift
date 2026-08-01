import Foundation

struct CommunityMigrationResult: Equatable, Sendable {
    let importedItemCount: Int
    let rollbackBackupURL: URL?
}
