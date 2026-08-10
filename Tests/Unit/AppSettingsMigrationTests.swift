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

    func testAppearanceDefaultsToSystemAndMapsEveryOption() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            XCTAssertEqual(settings.appearance, .system)
            XCTAssertNil(AppAppearance.system.colorScheme)
            XCTAssertEqual(AppAppearance.light.colorScheme, .light)
            XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
            XCTAssertEqual(AppAppearance.system.title, String(localized: "System"))
            XCTAssertEqual(AppAppearance.light.title, String(localized: "Light"))
            XCTAssertEqual(AppAppearance.dark.title, String(localized: "Dark"))
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

    func testEveryPreferencePersistsAndDerivedSetsNormalizeInput() {
        withDefaults { defaults in
            defaults.set(1, forKey: "closePanelAfterCopyingMigrationVersion")
            defaults.set(1, forKey: "applicationLockMigrationVersion")
            let settings = AppSettings(defaults: defaults)
            settings.globalShortcutEnabled = false
            settings.thumbnailCacheMegabytes = 96
            settings.allowedBundleIdentifiersText = " COM.Example.Allowed;com.example.second "
            settings.imageRetentionDays = 21
            settings.maximumStorageMegabytes = 512
            settings.privateModeDefaultEnabled = true
            settings.captureRichText = false
            settings.capturePDFs = false
            settings.captureFiles = false
            settings.imageTextRecognitionEnabled = false
            settings.ignoreUniversalClipboard = true
            settings.ignoredPasteboardTypesText = " COM.Example.Custom,com.example.other "
            settings.pasteStackRemovesUsedItems = false
            settings.globalShortcutPresetID = "command-option-v"
            settings.shortcutActivationMode = .hold
            settings.appearance = .dark
            settings.panelPresentationMode = .detachable
            settings.panelScreenEdge = .left
            settings.scrollReversalEnabled = true
            settings.reverseDiscreteScrollVertical = false
            settings.reverseDiscreteScrollHorizontal = false
            settings.reversePreciseScrollVertical = true
            settings.reversePreciseScrollHorizontal = true

            XCTAssertEqual(
                settings.allowedBundleIdentifiers,
                ["com.example.allowed", "com.example.second"]
            )
            XCTAssertEqual(
                settings.ignoredPasteboardTypes,
                [
                    "com.example.custom",
                    "com.example.other",
                    "com.apple.is-remote-clipboard"
                ]
            )
            XCTAssertEqual(settings.globalShortcut.id, "command-option-v")
            settings.globalShortcutPresetID = "unknown"
            XCTAssertEqual(settings.globalShortcut, GlobalShortcut.defaultShortcut)

            let reopened = AppSettings(defaults: defaults)
            XCTAssertFalse(reopened.globalShortcutEnabled)
            XCTAssertEqual(reopened.thumbnailCacheMegabytes, 96)
            XCTAssertTrue(reopened.privateModeDefaultEnabled)
            XCTAssertFalse(reopened.captureRichText)
            XCTAssertFalse(reopened.capturePDFs)
            XCTAssertFalse(reopened.captureFiles)
            XCTAssertFalse(reopened.imageTextRecognitionEnabled)
            XCTAssertFalse(reopened.pasteStackRemovesUsedItems)
            XCTAssertEqual(reopened.shortcutActivationMode, .hold)
            XCTAssertEqual(reopened.appearance, .dark)
            XCTAssertEqual(reopened.panelPresentationMode, .detachable)
            XCTAssertEqual(reopened.panelScreenEdge, .left)
            XCTAssertTrue(reopened.scrollReversalEnabled)
            XCTAssertFalse(reopened.reverseDiscreteScrollVertical)
            XCTAssertFalse(reopened.reverseDiscreteScrollHorizontal)
            XCTAssertTrue(reopened.reversePreciseScrollVertical)
            XCTAssertTrue(reopened.reversePreciseScrollHorizontal)
        }
    }

    func testScrollReversalUsesSafeDefaults() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)

            XCTAssertFalse(settings.scrollReversalEnabled)
            XCTAssertTrue(settings.reverseDiscreteScrollVertical)
            XCTAssertTrue(settings.reverseDiscreteScrollHorizontal)
            XCTAssertFalse(settings.reversePreciseScrollVertical)
            XCTAssertFalse(settings.reversePreciseScrollHorizontal)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AppSettingsMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
