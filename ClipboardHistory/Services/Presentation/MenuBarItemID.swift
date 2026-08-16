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

    var accessibilityIdentifier: String {
        switch self {
        case .controlCenter: "menuBar.controlCenter"
        case let .feature(id): "menuBar.feature.\(id.rawValue)"
        case .metricGroup: "menuBar.metrics.combined"
        case let .metric(id): "menuBar.metric.\(id.rawValue)"
        }
    }
}
