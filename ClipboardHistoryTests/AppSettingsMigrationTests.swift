import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class AppSettingsMigrationTests: XCTestCase {
    func testCloseAfterCopyingDefaultsToDisabled() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            XCTAssertFalse(settings.closePanelAfterCopying)
        }
    }

    func testMigrationDisablesExistingEnabledValueOnce() {
        withDefaults { defaults in
            defaults.set(true, forKey: "closePanelAfterCopying")

            let migrated = AppSettings(defaults: defaults)
            XCTAssertFalse(migrated.closePanelAfterCopying)

            migrated.closePanelAfterCopying = true
            let reopened = AppSettings(defaults: defaults)
            XCTAssertTrue(reopened.closePanelAfterCopying)
        }
    }

    func testApplicationLockDefaultsToDisabledWithLockedCaptureEnabled() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            XCTAssertFalse(settings.applicationLockEnabled)
            XCTAssertTrue(settings.captureWhileLocked)
            XCTAssertEqual(settings.autoLockOption, .never)
            XCTAssertEqual(defaults.integer(forKey: "applicationLockMigrationVersion"), 1)
        }
    }

    func testLegacyAutomaticLockMigrationPreservesExistingPrivacyBehavior() {
        withDefaults { defaults in
            defaults.set(AutoLockOption.fiveMinutes.rawValue, forKey: "autoLockOption")

            let settings = AppSettings(defaults: defaults)

            XCTAssertTrue(settings.applicationLockEnabled)
            XCTAssertFalse(settings.captureWhileLocked)
            XCTAssertEqual(settings.autoLockOption, .fiveMinutes)
        }
    }

    func testMigratedApplicationLockPreferencesPersist() {
        withDefaults { defaults in
            defaults.set(1, forKey: "applicationLockMigrationVersion")
            defaults.set(true, forKey: "applicationLockEnabled")
            defaults.set(false, forKey: "captureWhileLocked")

            let settings = AppSettings(defaults: defaults)
            XCTAssertTrue(settings.applicationLockEnabled)
            XCTAssertFalse(settings.captureWhileLocked)

            settings.setApplicationLockEnabled(false)
            settings.captureWhileLocked = true
            let reopened = AppSettings(defaults: defaults)
            XCTAssertFalse(reopened.applicationLockEnabled)
            XCTAssertTrue(reopened.captureWhileLocked)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AppSettingsMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
