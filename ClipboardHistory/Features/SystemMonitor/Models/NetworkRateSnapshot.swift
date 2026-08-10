import Foundation

struct NetworkRateSnapshot: Equatable, Sendable {
    var receivedBytesPerSecond: Double
    var sentBytesPerSecond: Double
    var interfaceName: String?

    static let empty = NetworkRateSnapshot(
        receivedBytesPerSecond: 0,
        sentBytesPerSecond: 0,
        interfaceName: nil
    )
}
