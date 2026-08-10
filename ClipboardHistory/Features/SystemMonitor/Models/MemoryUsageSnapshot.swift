import Foundation

struct MemoryUsageSnapshot: Equatable, Sendable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var activeBytes: UInt64
    var inactiveBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var cachedBytes: UInt64
    var freeBytes: UInt64
    var pressure: MemoryPressureLevel

    static let empty = MemoryUsageSnapshot(
        totalBytes: 0,
        usedBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        freeBytes: 0,
        pressure: .normal
    )

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}
