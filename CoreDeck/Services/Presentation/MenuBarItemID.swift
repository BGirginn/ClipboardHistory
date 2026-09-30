import Foundation

enum MenuBarItemID: Hashable {
    case controlCenter
    case drawer
    case feature(UtilityFeatureID)
    case metricGroup
    case metric(MenuBarMetricID)

    var autosaveName: String {
        switch self {
        case .controlCenter: "CoreDeck.ControlCenter"
        case .drawer: "CoreDeck.Drawer"
        case let .feature(id): "CoreDeck.Feature.\(id.rawValue)"
        case .metricGroup: "CoreDeck.Metrics.Combined"
        case let .metric(id): "CoreDeck.Metric.\(id.rawValue)"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .controlCenter: "menuBar.controlCenter"
        case .drawer: "menuBar.drawer"
        case let .feature(id): "menuBar.feature.\(id.rawValue)"
        case .metricGroup: "menuBar.metrics.combined"
        case let .metric(id): "menuBar.metric.\(id.rawValue)"
        }
    }
}
