import Foundation

enum SystemMetricsDemand: Hashable, Sendable {
    case detail
    case menuBar
    case controlCenter

    var interval: Duration {
        switch self {
        case .detail: .seconds(1)
        case .menuBar: .seconds(2)
        case .controlCenter: .seconds(5)
        }
    }
}
