import Foundation

struct StorageMutationOutcome: Equatable, Sendable {
    let persistentChangeCommitted: Bool
    let cleanupFailures: [String]

    static let committed = StorageMutationOutcome(
        persistentChangeCommitted: true,
        cleanupFailures: []
    )

    var requiresCleanupRetry: Bool {
        !cleanupFailures.isEmpty
    }
}
