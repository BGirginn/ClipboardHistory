import XCTest

@testable import ClipboardHistory

@MainActor
final class ControlCenterConfigurationTests: XCTestCase {
    func testDefaultsUseOneControlCenterItemAndKeepExperimentalAudioMixerHidden() {
        let context = makeContext()

        XCTAssertTrue(context.model.configuration.showsControlCenterItem)
        XCTAssertEqual(
            context.model.controlCenterFeatures.map(\.id),
            UtilityFeatureID.allCases.filter { $0 != .audioMixer }
        )
        XCTAssertTrue(context.model.standaloneFeatures.isEmpty)
        XCTAssertEqual(context.model.configuration.metricGroup, .defaults)
        XCTAssertTrue(context.model.configuration.metricGroup.metrics.isEmpty)
        XCTAssertEqual(
            context.model.configuration(for: .notes).clickAction,
            .open
        )
    }

    func testPlacementAndSupportedActionPersist() {
        let context = makeContext()
        context.model.setShownInControlCenter(false, for: .notes)
        context.model.setStandaloneItemVisible(true, for: .notes)
        context.model.setClickAction(.newNote, for: .notes)

        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        )
        XCTAssertFalse(reloaded.configuration(for: .notes).placement.showsInControlCenter)
        XCTAssertTrue(reloaded.configuration(for: .notes).placement.showsStandaloneItem)
        XCTAssertEqual(reloaded.configuration(for: .notes).clickAction, .newNote)
    }

    func testUnsupportedActionFallsBackAndNewRegistryFeaturesAreMigrated() throws {
        let context = makeContext()
        let invalid = MenuBarConfiguration(
            version: 0,
            showsControlCenterItem: false,
            features: [
                UtilityFeatureConfiguration(
                    id: .clipboard,
                    placement: FeaturePlacement(
                        showsInControlCenter: false,
                        showsStandaloneItem: true
                    ),
                    clickAction: .newNote
                )
            ]
        )
        context.defaults.set(try JSONEncoder().encode(invalid), forKey: "menuBarConfiguration.v1")

        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        )
        XCTAssertEqual(reloaded.configuration.features.count, UtilityFeatureID.allCases.count)
        XCTAssertEqual(reloaded.configuration(for: .clipboard).clickAction, .open)
        XCTAssertTrue(reloaded.configuration.showsControlCenterItem)
    }

    func testControlCenterItemCanBeHiddenWithoutAnotherMenuBarItem() {
        let context = makeContext()

        context.model.setControlCenterItemVisible(false)

        XCTAssertFalse(context.model.configuration.showsControlCenterItem)
        XCTAssertFalse(
            ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: context.defaults)
            ).configuration.showsControlCenterItem
        )
    }

    func testLegacyConfigurationRequiresFreshTopBarOptIn() throws {
        let context = makeContext()
        let legacyJSON = """
        {
          "version": 1,
          "showsControlCenterItem": false,
          "features": [
            {
              "id": "notes",
              "placement": { "showsInControlCenter": false, "showsStandaloneItem": true },
              "clickAction": "newNote"
            }
          ]
        }
        """
        context.defaults.set(Data(legacyJSON.utf8), forKey: "menuBarConfiguration.v1")

        let migrated = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        ).configuration

        XCTAssertEqual(migrated.version, 6)
        XCTAssertTrue(migrated.showsControlCenterItem)
        let notes = try XCTUnwrap(migrated.features.first { $0.id == .notes })
        XCTAssertFalse(notes.placement.showsInControlCenter)
        XCTAssertFalse(notes.placement.showsStandaloneItem)
        XCTAssertEqual(notes.clickAction, .newNote)
        XCTAssertEqual(migrated.metricGroup, .defaults)
        XCTAssertEqual(migrated.metricFormats, .defaults)
        XCTAssertNotNil(migrated.features.first { $0.id == .systemMonitor })
        XCTAssertNotNil(migrated.features.first { $0.id == .audioMixer })

        let persisted = try XCTUnwrap(
            context.defaults.data(forKey: "menuBarConfiguration.v1")
        )
        XCTAssertEqual(
            try JSONDecoder().decode(MenuBarConfiguration.self, from: persisted),
            migrated
        )
    }

    func testVersionThreeVisibleMetricsAndStandaloneItemsResetOnce() throws {
        let context = makeContext()
        var legacy = MenuBarConfiguration.defaults()
        legacy.version = 3
        legacy.features[0].placement.showsStandaloneItem = true
        legacy.metricGroup = MenuBarDisplayGroup(
            isVisible: true,
            showsSeparateItems: true,
            metrics: [.cpu, .memory, .temperature],
            style: .compact
        )
        context.defaults.set(try JSONEncoder().encode(legacy), forKey: "menuBarConfiguration.v1")

        let migrated = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        ).configuration

        XCTAssertEqual(migrated.version, 6)
        XCTAssertTrue(
            migrated.features.allSatisfy { !$0.placement.showsStandaloneItem }
        )
        XCTAssertEqual(migrated.metricGroup, .defaults)

        context.defaults.set(try JSONEncoder().encode(migrated), forKey: "menuBarConfiguration.v1")
        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        ).configuration
        XCTAssertEqual(reloaded, migrated)
    }

    func testEveryModuleAcceptsOnlyItsDeclaredClickActions() {
        let registry = FeatureRegistry.live

        for descriptor in registry.descriptors {
            XCTAssertTrue(descriptor.supportedClickActions.contains(descriptor.defaultClickAction))
            for action in FeatureClickAction.allCases where !descriptor.supportedClickActions.contains(action) {
                XCTAssertEqual(
                    registry.validatedAction(action, for: descriptor.id),
                    descriptor.defaultClickAction
                )
            }
        }
    }

    func testVersionThreeFormatsPersistAndEmptyMetricGroupKeepsWindowOnlyConfiguration() throws {
        let context = makeContext()
        var formats = MetricFormatPreferences.defaults
        formats.memory = .usedAndTotal
        formats.temperature = .fahrenheit
        formats.rate = .megabytes
        context.model.setMetricFormats(formats)

        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        )
        XCTAssertEqual(reloaded.configuration.metricFormats, formats)

        let invalid = MenuBarConfiguration(
            version: MenuBarConfiguration.currentVersion,
            showsControlCenterItem: false,
            features: reloaded.configuration.features.map {
                var feature = $0
                feature.placement.showsStandaloneItem = false
                return feature
            },
            metricGroup: MenuBarDisplayGroup(
                isVisible: true,
                showsSeparateItems: false,
                metrics: [],
                style: .compact
            )
        )
        context.defaults.set(try JSONEncoder().encode(invalid), forKey: "menuBarConfiguration.v1")
        XCTAssertFalse(
            ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: context.defaults)
            ).configuration.showsControlCenterItem
        )
    }

    func testMetricVisibilityOrderingAndBoundaryMovesPersist() {
        let context = makeContext()

        for metric in MenuBarMetricID.allCases {
            context.model.setMetricVisible(false, metric: metric)
        }
        XCTAssertTrue(context.model.configuration.metricGroup.metrics.isEmpty)
        XCTAssertFalse(context.model.configuration.metricGroup.isVisible)

        context.model.setMetricGroupVisible(true)
        XCTAssertTrue(context.model.configuration.metricGroup.isVisible)
        XCTAssertEqual(
            context.model.configuration.metricGroup.metrics,
            MenuBarConfiguration.defaultMenuBarMetrics
        )
        XCTAssertTrue(
            context.model.configuration(for: .systemMonitor).placement.showsStandaloneItem
        )
        for metric in MenuBarConfiguration.defaultMenuBarMetrics {
            context.model.setMetricVisible(false, metric: metric)
        }

        context.model.setMetricVisible(true, metric: .memory)
        XCTAssertTrue(context.model.configuration.metricGroup.isVisible)
        context.model.setMetricVisible(true, metric: .cpu)
        XCTAssertEqual(context.model.configuration.metricGroup.metrics, [.memory, .cpu])

        context.model.moveMetric(.cpu, direction: -1)
        XCTAssertEqual(context.model.configuration.metricGroup.metrics, [.cpu, .memory])
        context.model.moveMetric(.cpu, direction: -1)
        context.model.moveMetric(.memory, direction: 1)
        context.model.moveMetric(.temperature, direction: 1)
        XCTAssertEqual(context.model.configuration.metricGroup.metrics, [.cpu, .memory])

        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        )
        XCTAssertEqual(reloaded.configuration.metricGroup.metrics, [.cpu, .memory])
        XCTAssertTrue(reloaded.showsSystemMetricsInMenuBar)
    }

    func testStandaloneSystemMonitorUsesTheCanonicalLiveMetricsPreference() {
        let context = makeContext()

        context.model.setStandaloneItemVisible(true, for: .systemMonitor)

        XCTAssertTrue(context.model.showsSystemMetricsInMenuBar)
        XCTAssertTrue(context.model.configuration.metricGroup.isVisible)
        XCTAssertEqual(
            context.model.configuration.metricGroup.metrics,
            MenuBarConfiguration.defaultMenuBarMetrics
        )

        context.model.setMetricGroupVisible(false)

        XCTAssertFalse(context.model.showsSystemMetricsInMenuBar)
        XCTAssertFalse(
            context.model.configuration(for: .systemMonitor).placement.showsStandaloneItem
        )
    }

    func testCurrentStandaloneSystemMonitorConfigurationMigratesToLiveMetrics() throws {
        let context = makeContext()
        var stored = MenuBarConfiguration.defaults()
        let systemMonitorIndex = try XCTUnwrap(
            stored.features.firstIndex { $0.id == .systemMonitor }
        )
        stored.features[systemMonitorIndex].placement.showsStandaloneItem = true
        context.defaults.set(
            try JSONEncoder().encode(stored),
            forKey: "menuBarConfiguration.v1"
        )

        let reloaded = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        )

        XCTAssertTrue(reloaded.showsSystemMetricsInMenuBar)
        XCTAssertTrue(reloaded.configuration.metricGroup.isVisible)
        XCTAssertEqual(
            reloaded.configuration.metricGroup.metrics,
            MenuBarConfiguration.defaultMenuBarMetrics
        )
    }

    func testVersionFourVisibilityMigratesWithoutChangingUserPlacement() throws {
        let context = makeContext()
        let legacyJSON = """
        {
          "version": 4,
          "showsControlCenterItem": true,
          "features": [
            {
              "id": "clipboard",
              "placement": { "showsInControlCenter": true, "showsStandaloneItem": true },
              "clickAction": "open"
            },
            {
              "id": "notes",
              "placement": { "showsInControlCenter": true, "showsStandaloneItem": false },
              "clickAction": "open"
            }
          ],
          "metricGroup": {
            "isVisible": true,
            "showsSeparateItems": false,
            "metrics": ["memory", "cpu", "temperature"],
            "style": "iconAndValue"
          },
          "metricFormats": {
            "memory": "percentage",
            "temperature": "celsius",
            "rate": "automatic"
          }
        }
        """
        context.defaults.set(Data(legacyJSON.utf8), forKey: "menuBarConfiguration.v1")

        let migrated = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        ).configuration

        XCTAssertEqual(migrated.version, 6)
        XCTAssertEqual(
            migrated.features.first { $0.id == .clipboard }?.placement.menuBarVisibility,
            .always
        )
        XCTAssertEqual(
            migrated.features.first { $0.id == .notes }?.placement.menuBarVisibility,
            .hidden
        )
        XCTAssertEqual(migrated.metricGroup.metrics, [.memory, .cpu, .temperature])
        XCTAssertTrue(migrated.metricGroup.showsSeparateItems)
        XCTAssertEqual(migrated.metricGroup.density, .standard)
    }

    func testVersionFiveVisibleMetricsMigrateToSeparateItemsWithoutChangingOrderOrFormat() throws {
        let context = makeContext()
        var stored = MenuBarConfiguration.defaults()
        stored.version = 5
        stored.metricGroup = MenuBarDisplayGroup(
            isVisible: true,
            showsSeparateItems: false,
            metrics: [.memory, .temperature, .cpu],
            style: .compact,
            density: .compact
        )
        stored.metricFormats.temperature = .fahrenheit
        context.defaults.set(try JSONEncoder().encode(stored), forKey: "menuBarConfiguration.v1")

        let migrated = ControlCenterModel(
            store: MenuBarConfigurationStore(defaults: context.defaults)
        ).configuration

        XCTAssertEqual(migrated.version, 6)
        XCTAssertTrue(migrated.metricGroup.showsSeparateItems)
        XCTAssertEqual(migrated.metricGroup.metrics, [.memory, .temperature, .cpu])
        XCTAssertEqual(migrated.metricGroup.style, .compact)
        XCTAssertEqual(migrated.metricGroup.density, .compact)
        XCTAssertEqual(migrated.metricFormats.temperature, .fahrenheit)
    }

    func testBalancedAndMinimalPresetsProduceSmartHybridPolicies() {
        let context = makeContext()

        context.model.applyPreset(.balanced)

        XCTAssertEqual(context.model.selectedPreset, .balanced)
        XCTAssertTrue(context.model.configuration.metricGroup.isVisible)
        XCTAssertTrue(context.model.configuration.metricGroup.showsSeparateItems)
        XCTAssertEqual(context.model.configuration.metricGroup.density, .standard)
        XCTAssertEqual(
            context.model.configuration(for: .clipboard).placement.menuBarVisibility,
            .whenActive
        )
        XCTAssertEqual(
            context.model.configuration(for: .keyboardCleaning).placement.menuBarVisibility,
            .whenActive
        )
        XCTAssertEqual(
            context.model.configuration(for: .notes).placement.menuBarVisibility,
            .hidden
        )

        context.model.applyPreset(.minimal)

        XCTAssertEqual(context.model.selectedPreset, .minimal)
        XCTAssertFalse(context.model.configuration.metricGroup.isVisible)
        XCTAssertTrue(context.model.configuration.features.allSatisfy {
            $0.placement.menuBarVisibility == .hidden
        })
    }

    func testUnsupportedWhenActivePolicyIsNotPersisted() {
        let context = makeContext()

        context.model.setMenuBarVisibility(.whenActive, for: .notes)

        XCTAssertEqual(
            context.model.configuration(for: .notes).placement.menuBarVisibility,
            .hidden
        )
    }

    private func makeContext() -> (model: ControlCenterModel, defaults: UserDefaults) {
        let suite = "ControlCenterConfigurationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (
            ControlCenterModel(store: MenuBarConfigurationStore(defaults: defaults)),
            defaults
        )
    }
}
