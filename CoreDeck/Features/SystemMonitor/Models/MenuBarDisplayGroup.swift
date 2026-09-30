import Foundation

struct MenuBarDisplayGroup: Codable, Equatable {
    var isVisible: Bool
    var showsSeparateItems: Bool
    var metrics: [MenuBarMetricID]
    var style: MenuBarMetricStyle
    var density: MenuBarMetricDensity

    static let defaults = MenuBarDisplayGroup(
        isVisible: false,
        showsSeparateItems: true,
        metrics: [],
        style: .iconAndValue,
        density: .standard
    )

    init(
        isVisible: Bool,
        showsSeparateItems: Bool,
        metrics: [MenuBarMetricID],
        style: MenuBarMetricStyle,
        density: MenuBarMetricDensity = .standard
    ) {
        self.isVisible = isVisible
        self.showsSeparateItems = showsSeparateItems
        self.metrics = metrics
        self.style = style
        self.density = density
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case showsSeparateItems
        case metrics
        case style
        case density
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        showsSeparateItems = try container.decode(Bool.self, forKey: .showsSeparateItems)
        metrics = try container.decode([MenuBarMetricID].self, forKey: .metrics)
        style = try container.decode(MenuBarMetricStyle.self, forKey: .style)
        density = try container.decodeIfPresent(
            MenuBarMetricDensity.self,
            forKey: .density
        ) ?? .standard
    }
}
