import Foundation

struct CleanupReport: Equatable, Sendable {
    let removedItemCount: Int
    let reclaimedBytes: Int64
}
