import Foundation

struct MenuBarConfiguration: Codable, Equatable {
    static let currentVersion = 4

    var version: Int
    var showsControlCenterItem: Bool
    var features: [UtilityFeatureConfiguration]
    var metricGroup: MenuBarDisplayGroup
    var metricFormats: MetricFormatPreferences

    static func defaults(registry: FeatureRegistry = .live) -> MenuBarConfiguration {
        MenuBarConfiguration(
            version: currentVersion,
            showsControlCenterItem: true,
            features: registry.descriptors.map { descriptor in
                UtilityFeatureConfiguration(
                    id: descriptor.id,
                    placement: FeaturePlacement(
                        showsInControlCenter: descriptor.id != .audioMixer,
                        showsStandaloneItem: false
                    ),
                    clickAction: descriptor.defaultClickAction
                )
            },
            metricGroup: .defaults,
            metricFormats: .defaults
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case showsControlCenterItem
        case features
        case metricGroup
        case metricFormats
    }

    init(
        version: Int,
        showsControlCenterItem: Bool,
        features: [UtilityFeatureConfiguration],
        metricGroup: MenuBarDisplayGroup = .defaults,
        metricFormats: MetricFormatPreferences = .defaults
    ) {
        self.version = version
        self.showsControlCenterItem = showsControlCenterItem
        self.features = features
        self.metricGroup = metricGroup
        self.metricFormats = metricFormats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        showsControlCenterItem = try container.decode(Bool.self, forKey: .showsControlCenterItem)
        features = try container.decode([UtilityFeatureConfiguration].self, forKey: .features)
        metricGroup = try container.decodeIfPresent(MenuBarDisplayGroup.self, forKey: .metricGroup) ?? .defaults
        metricFormats = try container.decodeIfPresent(
            MetricFormatPreferences.self,
            forKey: .metricFormats
        ) ?? .defaults
    }
}
