import Foundation

struct MenuBarConfigurationStore {
    private static let storageKey = "menuBarConfiguration.v1"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func load(registry: FeatureRegistry = .live) -> MenuBarConfiguration {
        guard let data = defaults.data(forKey: key),
              let stored = try? decoder.decode(MenuBarConfiguration.self, from: data) else {
            return .defaults(registry: registry)
        }
        let normalized = Self.normalized(stored, registry: registry)
        if normalized != stored {
            save(normalized)
        }
        return normalized
    }

    func save(_ configuration: MenuBarConfiguration) {
        guard let data = try? encoder.encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }

    static func normalized(
        _ configuration: MenuBarConfiguration,
        registry: FeatureRegistry
    ) -> MenuBarConfiguration {
        let requiresExplicitTopBarOptIn = configuration.version < 4
        let storedByID = Dictionary(
            configuration.features.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var features = registry.descriptors.map { descriptor in
            var feature = storedByID[descriptor.id] ?? UtilityFeatureConfiguration(
                id: descriptor.id,
                placement: FeaturePlacement(
                    showsInControlCenter: descriptor.id != .audioMixer,
                    showsStandaloneItem: false
                ),
                clickAction: descriptor.defaultClickAction
            )
            if requiresExplicitTopBarOptIn {
                feature.placement.showsStandaloneItem = false
            }
            feature.clickAction = registry.validatedAction(feature.clickAction, for: feature.id)
            return feature
        }
        var metricGroup = requiresExplicitTopBarOptIn
            ? MenuBarDisplayGroup.defaults
            : configuration.metricGroup
        if (4..<MenuBarConfiguration.currentVersion).contains(configuration.version),
           metricGroup.isVisible {
            metricGroup.showsSeparateItems = true
        }
        let systemMonitorIndex = features.firstIndex { $0.id == .systemMonitor }
        let hasLegacySystemMonitorItem = systemMonitorIndex.map {
            features[$0].placement.showsStandaloneItem
        } ?? false
        if metricGroup.isVisible || hasLegacySystemMonitorItem {
            metricGroup.isVisible = true
            if metricGroup.metrics.isEmpty {
                metricGroup.metrics = MenuBarConfiguration.defaultMenuBarMetrics
            }
            if let systemMonitorIndex {
                features[systemMonitorIndex].placement.showsStandaloneItem = true
            }
        }

        return MenuBarConfiguration(
            version: MenuBarConfiguration.currentVersion,
            showsControlCenterItem: requiresExplicitTopBarOptIn
                ? true
                : configuration.showsControlCenterItem,
            features: features,
            metricGroup: metricGroup,
            metricFormats: configuration.metricFormats
        )
    }
}
