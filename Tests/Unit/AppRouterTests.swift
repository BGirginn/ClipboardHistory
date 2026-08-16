import XCTest

@testable import ClipboardHistory

@MainActor
final class AppRouterTests: XCTestCase {
    func testStartsAtControlCenterAndRoutesBetweenFeatures() {
        let router = AppRouter()

        XCTAssertEqual(router.activeFeature, .controlCenter)
        router.showClipboard()
        XCTAssertEqual(router.activeFeature, .clipboard)
        router.showNotes()
        XCTAssertEqual(router.activeFeature, .notes)
        router.showKeyboardCleaning()
        XCTAssertEqual(router.activeFeature, .keyboardCleaning)
        router.showScrollReverse()
        XCTAssertEqual(router.activeFeature, .scrollReverse)
        router.showMenuBarCustomization()
        XCTAssertEqual(router.activeFeature, .menuBarCustomization)
        router.showControlCenter()
        XCTAssertEqual(router.activeFeature, .controlCenter)
    }

    func testSettingsReturnsToCallingFeature() {
        let router = AppRouter(activeFeature: .notes)

        router.openSettings(section: .menuBar)
        XCTAssertEqual(router.activeFeature, .settings)
        XCTAssertEqual(router.settingsReturnFeature, .notes)
        XCTAssertEqual(router.settingsSection, .menuBar)

        router.openSettings(section: .inputTools)
        XCTAssertEqual(router.settingsReturnFeature, .notes)
        XCTAssertEqual(router.settingsSection, .inputTools)

        router.closeSettings()
        XCTAssertEqual(router.activeFeature, .notes)
    }

    func testEverySettingsSectionOwnsItsDefaultSubsection() {
        let allSubsections = AppSettingsSection.allCases.flatMap(\.subsections)

        for section in AppSettingsSection.allCases {
            XCTAssertFalse(section.subsections.isEmpty)
            XCTAssertTrue(section.subsections.contains(section.defaultSubsection))
        }
        XCTAssertEqual(Set(allSubsections).count, allSubsections.count)
    }

}
