import Foundation

struct StorageMetrics: Equatable, Sendable {
    let databaseBytes: Int64
    let imageBytes: Int64
    let thumbnailBytes: Int64
    let payloadBytes: Int64

    var totalBytes: Int64 {
        databaseBytes + imageBytes + thumbnailBytes + payloadBytes
    }
}
