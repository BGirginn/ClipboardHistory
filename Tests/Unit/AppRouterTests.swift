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

        router.openSettings()
        XCTAssertEqual(router.activeFeature, .settings)
        XCTAssertEqual(router.settingsReturnFeature, .notes)

        router.closeSettings()
        XCTAssertEqual(router.activeFeature, .notes)
    }

    func testLockRecordsLocationWithoutReplacingIt() {
        let router = AppRouter(activeFeature: .notes)

        router.applicationLockDidChange(isLocked: true)
        XCTAssertEqual(router.featureBeforeLock, .notes)
        XCTAssertEqual(router.activeFeature, .notes)

        router.applicationLockDidChange(isLocked: false)
        XCTAssertNil(router.featureBeforeLock)
        XCTAssertEqual(router.activeFeature, .notes)
    }
}
