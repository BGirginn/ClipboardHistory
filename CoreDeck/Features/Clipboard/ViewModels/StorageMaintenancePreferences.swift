import Foundation

struct StorageMaintenancePreferences: Equatable, Sendable {
    let historyLimit: Int
    let retentionDays: Int
    let imageRetentionDays: Int
    let maximumStorageMegabytes: Int
    let thumbnailCacheMegabytes: Int
}
