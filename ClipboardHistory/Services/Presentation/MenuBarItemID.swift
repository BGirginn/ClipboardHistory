import Foundation

enum MenuBarItemID: Hashable {
    case controlCenter
    case feature(UtilityFeatureID)
    case metricGroup
    case metric(MenuBarMetricID)

    var autosaveName: String {
        switch self {
        case .controlCenter: "ClipboardHistory.ControlCenter"
        case let .feature(id): "ClipboardHistory.Feature.\(id.rawValue)"
        case .metricGroup: "ClipboardHistory.Metrics.Combined"
        case let .metric(id): "ClipboardHistory.Metric.\(id.rawValue)"
        }
    }
}
