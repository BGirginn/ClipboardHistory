import XCTest

@testable import ClipboardHistory

@MainActor
final class ControlCenterConfigurationTests: XCTestCase {
    func testDefaultsUseOneControlCenterItemAndShowEveryModuleInsideIt() {
        let context = makeContext()

        XCTAssertTrue(context.model.configuration.showsControlCenterItem)
        XCTAssertEqual(context.model.controlCenterFeatures.map(\.id), UtilityFeatureID.allCases)
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

    func testLastVisibleItemKeepsControlCenterAvailable() {
        let context = makeContext()

        context.model.setControlCenterItemVisible(false)

        XCTAssertTrue(context.model.configuration.showsControlCenterItem)
        XCTAssertEqual(
            context.model.feedbackMessage,
            "Control Center stays visible so the app remains accessible."
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

        XCTAssertEqual(migrated.version, 2)
        XCTAssertFalse(migrated.showsControlCenterItem)
        let notes = try XCTUnwrap(migrated.features.first { $0.id == .notes })
        XCTAssertFalse(notes.placement.showsInControlCenter)
        XCTAssertTrue(notes.placement.showsStandaloneItem)
        XCTAssertEqual(notes.clickAction, .newNote)
        XCTAssertEqual(migrated.metricGroup, .defaults)
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
