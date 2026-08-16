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
        XCTAssertFalse(reloaded.configuration.showsControlCenterItem)
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

    func testVersionOneConfigurationMigratesWithoutLosingExistingPlacements() throws {
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

        XCTAssertEqual(migrated.version, 3)
        XCTAssertFalse(migrated.showsControlCenterItem)
        let notes = try XCTUnwrap(migrated.features.first { $0.id == .notes })
        XCTAssertFalse(notes.placement.showsInControlCenter)
        XCTAssertTrue(notes.placement.showsStandaloneItem)
        XCTAssertEqual(notes.clickAction, .newNote)
        XCTAssertEqual(migrated.metricGroup, .defaults)
        XCTAssertEqual(migrated.metricFormats, .defaults)
        XCTAssertNotNil(migrated.features.first { $0.id == .systemMonitor })
        XCTAssertNotNil(migrated.features.first { $0.id == .audioMixer })
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
            version: 2,
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
        XCTAssertEqual(context.model.configuration.metricGroup.metrics, [.cpu])
        context.model.setMetricVisible(false, metric: .cpu)

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
