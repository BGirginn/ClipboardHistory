import Combine
import Foundation

@MainActor
final class ControlCenterModel: ObservableObject {
    @Published private(set) var configuration: MenuBarConfiguration
    @Published var feedbackMessage: String?

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
        registry.descriptors.filter { configuration(for: $0.id).placement.showsStandaloneItem }
    }

    func configuration(for id: UtilityFeatureID) -> UtilityFeatureConfiguration {
        configuration.features.first { $0.id == id }
            ?? MenuBarConfiguration.defaults(registry: registry).features.first { $0.id == id }!
    }

    func setControlCenterItemVisible(_ isVisible: Bool) {
        var updated = configuration
        updated.showsControlCenterItem = isVisible
        enforceVisibleItemInvariant(in: &updated)
        configuration = updated
        persist()
    }

    func setShownInControlCenter(_ isShown: Bool, for id: UtilityFeatureID) {
        updateFeature(id) { $0.placement.showsInControlCenter = isShown }
    }

    func setStandaloneItemVisible(_ isVisible: Bool, for id: UtilityFeatureID) {
        updateFeature(id, enforcingVisibleItem: true) {
            $0.placement.showsStandaloneItem = isVisible
        }
    }

    func setClickAction(_ action: FeatureClickAction, for id: UtilityFeatureID) {
        updateFeature(id) { feature in
            feature.clickAction = registry.validatedAction(action, for: id)
        }
    }

    func setMetricGroupVisible(_ isVisible: Bool) {
        var updated = configuration
        updated.metricGroup.isVisible = isVisible && !updated.metricGroup.metrics.isEmpty
        enforceVisibleItemInvariant(in: &updated)
        configuration = updated
        persist()
    }

    func setMetricsAsSeparateItems(_ isSeparate: Bool) {
        var updated = configuration
        updated.metricGroup.showsSeparateItems = isSeparate
        enforceVisibleItemInvariant(in: &updated)
        configuration = updated
        persist()
    }

    func setMetricStyle(_ style: MenuBarMetricStyle) {
        var updated = configuration
        updated.metricGroup.style = style
        configuration = updated
        persist()
    }

    func setMetricVisible(_ isVisible: Bool, metric: MenuBarMetricID) {
        var updated = configuration
        if isVisible {
            if !updated.metricGroup.metrics.contains(metric) {
                updated.metricGroup.metrics.append(metric)
            }
        } else {
            updated.metricGroup.metrics.removeAll { $0 == metric }
            if updated.metricGroup.metrics.isEmpty {
                updated.metricGroup.isVisible = false
            }
        }
        enforceVisibleItemInvariant(in: &updated)
        configuration = updated
        persist()
    }

    func setMetricFormats(_ formats: MetricFormatPreferences) {
        var updated = configuration
        updated.metricFormats = formats
        configuration = updated
        persist()
    }

    func moveMetric(_ metric: MenuBarMetricID, direction: Int) {
        var updated = configuration
        guard let index = updated.metricGroup.metrics.firstIndex(of: metric) else { return }
        let destination = index + direction
        guard updated.metricGroup.metrics.indices.contains(destination) else { return }
        updated.metricGroup.metrics.swapAt(index, destination)
        configuration = updated
        persist()
    }

    private func updateFeature(
        _ id: UtilityFeatureID,
        enforcingVisibleItem: Bool = false,
        mutation: (inout UtilityFeatureConfiguration) -> Void
    ) {
        var updated = configuration
        guard let index = updated.features.firstIndex(where: { $0.id == id }) else { return }
        mutation(&updated.features[index])
        if enforcingVisibleItem {
            enforceVisibleItemInvariant(in: &updated)
        }
        configuration = updated
        persist()
    }

    private func enforceVisibleItemInvariant(in configuration: inout MenuBarConfiguration) {
        guard !configuration.showsControlCenterItem,
              !configuration.features.contains(where: { $0.placement.showsStandaloneItem }),
              (!configuration.metricGroup.isVisible || configuration.metricGroup.metrics.isEmpty) else {
            return
        }
        configuration.showsControlCenterItem = true
        feedbackMessage = String(localized: "Control Center stays visible so the app remains accessible.")
    }

    private func persist() {
        store.save(configuration)
    }
}
