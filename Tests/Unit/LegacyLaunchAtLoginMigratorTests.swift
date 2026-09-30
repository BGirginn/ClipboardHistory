import Foundation
import XCTest

@testable import CoreDeckTestHost

@MainActor
final class LegacyLaunchAtLoginMigratorTests: XCTestCase {
    func testRegistersNewHelperOnlyOnceWhenLegacyPreferenceWasEnabled() throws {
        let prefix = "CoreDeckLoginMigration-\(UUID().uuidString)"
        let legacyDomain = "\(prefix).legacy"
        let currentDomain = "\(prefix).current"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: prefix))
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
        }
        defaults.setPersistentDomain(["launchAtLoginRequested": true], forName: legacyDomain)
        let backend = LegacyLoginBackend()
        let service = LaunchAtLoginService(backend: backend)
        let migrator = LegacyLaunchAtLoginMigrator(
            legacyDomain: legacyDomain, currentDomain: currentDomain
        )

        migrator.migrateIfNeeded(service: service, defaults: defaults)
        migrator.migrateIfNeeded(service: service, defaults: defaults)

        XCTAssertEqual(backend.registrationCount, 1)
        XCTAssertTrue(service.isEnabled)
    }

    func testDoesNotRegisterWhenLegacyPreferenceWasDisabled() throws {
        let prefix = "CoreDeckLoginMigration-\(UUID().uuidString)"
        let legacyDomain = "\(prefix).legacy"
        let currentDomain = "\(prefix).current"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: prefix))
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
        }
        defaults.setPersistentDomain(["launchAtLoginRequested": false], forName: legacyDomain)
        let backend = LegacyLoginBackend()
        let service = LaunchAtLoginService(backend: backend)

        LegacyLaunchAtLoginMigrator(legacyDomain: legacyDomain, currentDomain: currentDomain)
            .migrateIfNeeded(service: service, defaults: defaults)

        XCTAssertEqual(backend.registrationCount, 0)
        XCTAssertFalse(service.isEnabled)
    }

    func testRetriesRegistrationAfterServiceFailure() throws {
        let prefix = "CoreDeckLoginMigration-\(UUID().uuidString)"
        let legacyDomain = "\(prefix).legacy"
        let currentDomain = "\(prefix).current"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: prefix))
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: currentDomain)
        }
        defaults.setPersistentDomain(["launchAtLoginRequested": true], forName: legacyDomain)
        let backend = LegacyLoginBackend()
        backend.shouldFailRegistration = true
        let service = LaunchAtLoginService(backend: backend)
        let migrator = LegacyLaunchAtLoginMigrator(
            legacyDomain: legacyDomain, currentDomain: currentDomain
        )

        migrator.migrateIfNeeded(service: service, defaults: defaults)
        XCTAssertFalse(service.isEnabled)

        backend.shouldFailRegistration = false
        migrator.migrateIfNeeded(service: service, defaults: defaults)

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(backend.registrationCount, 1)
    }
}

@MainActor
private final class LegacyLoginBackend: LaunchAtLoginBackend {
    var isEnabled = false
    var shouldFailRegistration = false
    private(set) var registrationCount = 0

    func setEnabled(_ enabled: Bool) throws {
        if enabled && shouldFailRegistration {
            throw CocoaError(.fileWriteUnknown)
        }
        isEnabled = enabled
        if enabled { registrationCount += 1 }
    }
}
