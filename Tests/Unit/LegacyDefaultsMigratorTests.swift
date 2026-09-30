import Foundation
import XCTest

@testable import CoreDeckTestHost

final class LegacyDefaultsMigratorTests: XCTestCase {
    func testCopiesMissingPreferencesAndPreservesNewValues() throws {
        let prefix = "CoreDeckMigration-\(UUID().uuidString)"
        let legacyDomain = "\(prefix).legacy"
        let currentDomain = "\(prefix).current"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: prefix))
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
        }
        defaults.setPersistentDomain(
            ["historyLimit": 75, "menuBarConfiguration.v1": Data([1, 2, 3])],
            forName: legacyDomain
        )
        defaults.setPersistentDomain(
            ["historyLimit": 50], forName: currentDomain
        )

        LegacyDefaultsMigrator(legacyDomain: legacyDomain, currentDomain: currentDomain)
            .migrateIfNeeded(defaults: defaults)

        let current = try XCTUnwrap(defaults.persistentDomain(forName: currentDomain))
        XCTAssertEqual(current["historyLimit"] as? Int, 50)
        XCTAssertEqual(current["menuBarConfiguration.v1"] as? Data, Data([1, 2, 3]))
        XCTAssertNotNil(defaults.persistentDomain(forName: legacyDomain))

        var changed = current
        changed.removeValue(forKey: "menuBarConfiguration.v1")
        defaults.setPersistentDomain(changed, forName: currentDomain)
        LegacyDefaultsMigrator(legacyDomain: legacyDomain, currentDomain: currentDomain)
            .migrateIfNeeded(defaults: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: currentDomain)?["menuBarConfiguration.v1"])
    }
}
