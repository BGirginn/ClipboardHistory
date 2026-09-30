import Combine
import Foundation

@MainActor
final class ControlCenterModel: ObservableObject {
    @Published private(set) var configuration: MenuBarConfiguration
    @Published private(set) var areRequestedMenuBarItemsVisible = true

    let registry: FeatureRegistry
    private let store: MenuBarConfigurationStore

    init(
        registry: FeatureRegistry = .live,
        store: MenuBarConfigurationStore = MenuBarConfigurationStore()
    ) {
        self.registry = registry
        self.store = store
        configuration = store.load(registry: registry)
    }

    var controlCenterFeatures: [FeatureDescriptor] {
        registry.descriptors.filter { configuration(for: $0.id).placement.showsInControlCenter }
    }

    var standaloneFeatures: [FeatureDescriptor] {
        registry.descriptors.filter {
            $0.id != .systemMonitor
                && configuration(for: $0.id).placement.showsInTopBar
        }
    }

    var drawerFeatures: [FeatureDescriptor] {
        registry.descriptors.filter {
            configuration(for: $0.id).placement.showsInDrawer
        }
    }

    var selectedPreset: MenuBarPreset {
        if Self.isMinimal(configuration) { return .minimal }
        if Self.isBalanced(configuration) { return .balanced }
        return .custom
    }

    var showsSystemMetricsInMenuBar: Bool {
        configuration.showsSystemMetricsInMenuBar
    }

    func configuration(for id: UtilityFeatureID) -> UtilityFeatureConfiguration {
        if let stored = configuration.features.first(where: { $0.id == id }) {
            return stored
        }
        let descriptor = registry.descriptor(for: id)
        return UtilityFeatureConfiguration(
            id: id,
            placement: FeaturePlacement(
                showsInControlCenter: id != .audioMixer,
                showsStandaloneItem: false
            ),
            clickAction: descriptor?.defaultClickAction ?? .open
        )
    }

    func setControlCenterItemVisible(_ isVisible: Bool) {
        var updated = configuration
        updated.showsControlCenterItem = isVisible
        apply(updated)
    }

    func setDrawerItemVisible(_ isVisible: Bool) {
        var updated = configuration
        updated.showsDrawerItem = isVisible
        apply(updated)
    }

    func setShownInControlCenter(_ isShown: Bool, for id: UtilityFeatureID) {
        updateFeature(id) { $0.placement.showsInControlCenter = isShown }
    }

    func setStandaloneItemVisible(_ isVisible: Bool, for id: UtilityFeatureID) {
        if id == .systemMonitor {
            setSystemMetricsInMenuBarVisible(isVisible)
            return
        }
        updateFeature(id) {
            $0.placement.menuBarVisibility = isVisible ? .always : .hidden
            if isVisible { $0.placement.showsInDrawer = false }
        }
    }

    func setMenuBarVisibility(_ policy: MenuBarVisibilityPolicy, for id: UtilityFeatureID) {
        if id == .systemMonitor {
            setSystemMetricsInMenuBarVisible(policy != .hidden)
            return
        }
        guard registry.descriptor(for: id)?
            .supportedMenuBarVisibilityPolicies.contains(policy) == true else { return }
        updateFeature(id) {
            $0.placement.menuBarVisibility = policy
            if policy != .hidden {
                $0.placement.showsInDrawer = false
            }
        }
    }

    func setShownInDrawer(_ isShown: Bool, for id: UtilityFeatureID) {
        updateFeature(id) {
            $0.placement.showsInDrawer = isShown
        }
    }

    func restoreFeatureToMenuBar(_ id: UtilityFeatureID) {
        if id == .systemMonitor {
            setSystemMetricsInMenuBarVisible(true)
        } else {
            let policy = configuration(for: id).placement.menuBarVisibility
            setMenuBarVisibility(policy == .hidden ? .always : policy, for: id)
        }
    }

    func applyPreset(_ preset: MenuBarPreset) {
        guard preset != .custom else { return }
        var updated = configuration
        updated.showsControlCenterItem = true
        updated.showsDrawerItem = false
        for index in updated.features.indices {
            let id = updated.features[index].id
            updated.features[index].placement.showsInDrawer = false
            updated.features[index].placement.menuBarVisibility = switch (preset, id) {
            case (.balanced, .clipboard), (.balanced, .keyboardCleaning),
                 (.balanced, .scrollReverse), (.balanced, .audioMixer): .whenActive
            case (.balanced, .systemMonitor): .always
            default: .hidden
            }
        }
        if preset == .balanced {
            updated.metricGroup = MenuBarDisplayGroup(
                isVisible: true,
                showsSeparateItems: true,
                metrics: MenuBarConfiguration.defaultMenuBarMetrics,
                style: .iconAndValue,
                density: .standard
            )
        } else {
            updated.metricGroup = .defaults
        }
        apply(updated)
    }

    func setClickAction(_ action: FeatureClickAction, for id: UtilityFeatureID) {
        updateFeature(id) { feature in
            feature.clickAction = registry.validatedAction(action, for: id)
        }
    }

    func setMetricGroupVisible(_ isVisible: Bool) {
        setSystemMetricsInMenuBarVisible(isVisible)
    }

    private func setSystemMetricsInMenuBarVisible(_ isVisible: Bool) {
        var updated = configuration
        if isVisible && updated.metricGroup.metrics.isEmpty {
            updated.metricGroup.metrics = MenuBarConfiguration.defaultMenuBarMetrics
        }
        updated.metricGroup.isVisible = isVisible
        setSystemMonitorPlacement(isVisible, in: &updated)
        if isVisible, let index = updated.features.firstIndex(where: { $0.id == .systemMonitor }) {
            updated.features[index].placement.showsInDrawer = false
        }
        apply(updated)
    }

    func setMetricsAsSeparateItems(_ isSeparate: Bool) {
        var updated = configuration
        updated.metricGroup.showsSeparateItems = isSeparate
        apply(updated)
    }

    func setMetricStyle(_ style: MenuBarMetricStyle) {
        var updated = configuration
        updated.metricGroup.style = style
        apply(updated)
    }

    func setMetricDensity(_ density: MenuBarMetricDensity) {
        var updated = configuration
        updated.metricGroup.density = density
        apply(updated)
    }

    func setMetricVisible(_ isVisible: Bool, metric: MenuBarMetricID) {
        var updated = configuration
        if isVisible {
            if !updated.metricGroup.metrics.contains(metric) {
                updated.metricGroup.metrics.append(metric)
            }
            updated.metricGroup.isVisible = true
            setSystemMonitorPlacement(true, in: &updated)
        } else {
            updated.metricGroup.metrics.removeAll { $0 == metric }
            if updated.metricGroup.metrics.isEmpty {
                updated.metricGroup.isVisible = false
                setSystemMonitorPlacement(false, in: &updated)
            }
        }
        apply(updated)
    }

    func setMetricFormats(_ formats: MetricFormatPreferences) {
        var updated = configuration
        updated.metricFormats = formats
        apply(updated)
    }

    func moveMetric(_ metric: MenuBarMetricID, direction: Int) {
        var updated = configuration
        guard let index = updated.metricGroup.metrics.firstIndex(of: metric) else { return }
        let destination = index + direction
        guard updated.metricGroup.metrics.indices.contains(destination) else { return }
        updated.metricGroup.metrics.swapAt(index, destination)
        apply(updated)
    }

    func moveMetrics(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard offsets.count == 1, let source = offsets.first else { return }
        var updated = configuration
        guard updated.metricGroup.metrics.indices.contains(source) else { return }
        let metric = updated.metricGroup.metrics.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        let insertionIndex = min(max(adjustedDestination, 0), updated.metricGroup.metrics.count)
        updated.metricGroup.metrics.insert(metric, at: insertionIndex)
        apply(updated)
    }

    func setRequestedMenuBarItemsVisible(_ isVisible: Bool) {
        guard areRequestedMenuBarItemsVisible != isVisible else { return }
        areRequestedMenuBarItemsVisible = isVisible
    }

    private func updateFeature(
        _ id: UtilityFeatureID,
        mutation: (inout UtilityFeatureConfiguration) -> Void
    ) {
        var updated = configuration
        guard let index = updated.features.firstIndex(where: { $0.id == id }) else { return }
        mutation(&updated.features[index])
        apply(updated)
    }

    private func setSystemMonitorPlacement(
        _ isVisible: Bool,
        in configuration: inout MenuBarConfiguration
    ) {
        guard let index = configuration.features.firstIndex(where: {
            $0.id == .systemMonitor
        }) else {
            return
        }
        configuration.features[index].placement.showsStandaloneItem = isVisible
    }

    private static func isMinimal(_ configuration: MenuBarConfiguration) -> Bool {
        configuration.showsControlCenterItem
            && !configuration.showsDrawerItem
            && !configuration.metricGroup.isVisible
            && configuration.features.allSatisfy {
                $0.placement.menuBarVisibility == .hidden && !$0.placement.showsInDrawer
            }
    }

    private static func isBalanced(_ configuration: MenuBarConfiguration) -> Bool {
        guard configuration.showsControlCenterItem,
              !configuration.showsDrawerItem,
              configuration.metricGroup.isVisible,
              configuration.metricGroup.showsSeparateItems,
              configuration.metricGroup.metrics == MenuBarConfiguration.defaultMenuBarMetrics,
              configuration.metricGroup.style == .iconAndValue,
              configuration.metricGroup.density == .standard else { return false }
        return configuration.features.allSatisfy { feature in
            let expected: MenuBarVisibilityPolicy = switch feature.id {
            case .clipboard, .keyboardCleaning, .scrollReverse, .audioMixer: .whenActive
            case .systemMonitor: .always
            case .notes: .hidden
            }
            return feature.placement.menuBarVisibility == expected && !feature.placement.showsInDrawer
        }
    }

    private func apply(_ updated: MenuBarConfiguration) {
        guard updated != configuration else { return }
        configuration = updated
        store.save(updated)
    }
}
