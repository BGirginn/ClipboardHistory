import Foundation

struct MenuBarDisplayGroup: Codable, Equatable {
    var isVisible: Bool
    var showsSeparateItems: Bool
    var metrics: [MenuBarMetricID]
    var style: MenuBarMetricStyle

    static let defaults = MenuBarDisplayGroup(
        isVisible: false,
        showsSeparateItems: false,
        metrics: [],
        style: .iconAndValue
    )
}
