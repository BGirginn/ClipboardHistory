import Foundation

struct CPUUsageSnapshot: Equatable, Sendable {
    var totalPercent: Double
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var perCorePercent: [Double]

    static let empty = CPUUsageSnapshot(
        totalPercent: 0,
        userPercent: 0,
        systemPercent: 0,
        idlePercent: 100,
        perCorePercent: []
    )
}
